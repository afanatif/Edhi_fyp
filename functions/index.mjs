import {createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, Timestamp} from 'firebase-admin/firestore';
import {FieldValue} from 'firebase-admin/firestore';
import {getFunctions} from 'firebase-admin/functions';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onTaskDispatched} from 'firebase-functions/v2/tasks';
import {arrivalDeadline, canCommitArrival} from './arrival-policy.mjs';
import {onRequest} from 'firebase-functions/v2/https';
import {defineString} from 'firebase-functions/params';
import {createPhoneLogin, normalizePhone, PhoneLoginError} from './phone-login.mjs';

initializeApp();
const auth = getAuth();
const db = getFirestore();

// Optional Blaze backend: arrival also commits when every client is closed.
// Old scheduled tasks become harmless after pause, retiming, cancellation or reassignment.
export const scheduleAmbulanceArrival = onDocumentWritten({
  document: 'route_demos/{employeeId}', region: 'us-central1', maxInstances: 5,
}, async (event) => {
  const route = event.data?.after.data();
  const deadline = arrivalDeadline(route);
  if (!route?.enabled || route.pausedAt != null || route.stoppedAt != null || deadline === null || !route.points?.length) return;
  await getFunctions().taskQueue('locations/us-central1/functions/commitAmbulanceArrival').enqueue({
    employeeId: event.params.employeeId, requestId: route.requestId,
    startedAtMs: route.startedAt.toMillis(), durationSeconds: route.durationSeconds,
  }, {scheduleTime: new Date(Math.max(Date.now(), deadline)), dispatchDeadlineSeconds: 60});
});

export const commitAmbulanceArrival = onTaskDispatched({
  region: 'us-central1', retryConfig: {maxAttempts: 5, minBackoffSeconds: 2},
  rateLimits: {maxConcurrentDispatches: 10}, timeoutSeconds: 60, maxInstances: 5,
}, async ({data}) => {
  const {employeeId, requestId} = data;
  if (typeof employeeId !== 'string' || typeof requestId !== 'string' ||
      employeeId.includes('/') || requestId.includes('/') || !employeeId || !requestId) return;
  const routeRef = db.doc(`route_demos/${employeeId}`);
  const unitRef = db.doc(`employees/${employeeId}`);
  const jobRef = db.doc(`emergency_requests/${requestId}`);
  await db.runTransaction(async (tx) => {
    const [saved, employee, request] = await tx.getAll(routeRef, unitRef, jobRef);
    const route = saved.data();
    const deadline = arrivalDeadline(route);
    if (route?.enabled && route.requestId === requestId && route.pausedAt == null &&
        deadline !== null && Date.now() < deadline) throw new Error('Arrival deadline has not elapsed; retry.');
    if (!canCommitArrival({route, unit: employee.data(), job: request.data(), employeeId, expected: data, now: Date.now()})) return;
    const end = route.points.at(-1);
    tx.update(jobRef, {status: 'Arrived', updatedAt: FieldValue.serverTimestamp()});
    tx.update(unitRef, {currentLat: end.lat, currentLng: end.lng, speedKmh: 0});
    tx.update(routeRef, {enabled: false, stoppedAt: FieldValue.serverTimestamp()});
  });
});
const webApiKey = defineString('FIREBASE_WEB_API_KEY', {
  description: 'Web app apiKey from this Firebase project (Project settings → General).',
});

async function limitAttempt(phone, ip) {
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const limits = [[`phone:${phone}`, 10], [`ip:${ip || 'unknown'}`, 60]].map(([key, max]) => ({
    ref: db.collection('auth_login_limits').doc(createHash('sha256').update(key).digest('hex')), max,
  }));
  await db.runTransaction(async (tx) => {
    const docs = await Promise.all(limits.map(({ref}) => tx.get(ref)));
    const counts = docs.map((doc) => {
      const data = doc.data();
      return data && now - data.windowStartedAt < windowMs ? data.attempts : 0;
    });
    if (counts.some((count, index) => count >= limits[index].max)) {
      throw new PhoneLoginError(429, 'Too many attempts. Please wait and retry.');
    }
    limits.forEach(({ref}, index) => tx.set(ref, {
      attempts: counts[index] + 1,
      windowStartedAt: counts[index] ? docs[index].data().windowStartedAt : now,
      expiresAt: Timestamp.fromMillis(now + windowMs),
    }));
  });
}

async function findAccount(phone) {
  const claim = await db.collection('phone_claims').doc(phone).get();
  let profile;
  if (claim.exists && typeof claim.data().userId === 'string') {
    profile = await db.collection('users').doc(claim.data().userId).get();
  } else {
    // Older staff profiles may predate phone reservations.
    const digits = phone.slice(1);
    const matches = await db.collection('users').where('phone', 'in', [phone, digits, `0${digits.slice(2)}`]).limit(2).get();
    if (matches.size !== 1) return null;
    profile = matches.docs[0];
  }
  if (!profile.exists || normalizePhone(profile.data().phone) !== phone) return null;
  try {
    const user = await auth.getUser(profile.id);
    return {...profile.data(), uid: user.uid, email: user.email, disabled: user.disabled};
  } catch (error) {
    if (error.code === 'auth/user-not-found') return null;
    throw error;
  }
}

async function signInWithPassword(email, password) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(webApiKey.value())}`, {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true}),
    signal: AbortSignal.timeout(15000),
  });
  const body = await response.json();
  if (!response.ok) {
    const code = body.error?.message || '';
    if (code.startsWith('TOO_MANY_ATTEMPTS')) throw new PhoneLoginError(429, 'Too many attempts. Please wait and retry.');
    if (response.status >= 500 || code.startsWith('API_KEY') || code.startsWith('OPERATION_NOT_ALLOWED')) {
      throw new PhoneLoginError(503, 'Phone sign-in is temporarily unavailable.');
    }
    throw new PhoneLoginError(401, 'Invalid phone number or password.');
  }
  return body;
}

const login = createPhoneLogin({limitAttempt, findAccount, signInWithPassword,
  verifyIdToken: (token) => auth.verifyIdToken(token, true),
  createCustomToken: (uid) => auth.createCustomToken(uid)});

export const loginWithPhone = onRequest({region: 'us-central1', cors: true, timeoutSeconds: 30, maxInstances: 5}, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.set('Allow', 'POST');
    res.status(405).json({error: 'Use POST.'});
    return;
  }
  try {
    res.status(200).json(await login(req.body, req.ip));
  } catch (error) {
    // Never log request bodies, passwords, CNIC aliases, or session tokens.
    const known = error instanceof PhoneLoginError;
    res.status(known ? error.status : 503).json({error: known ? error.message : 'Phone sign-in is temporarily unavailable.'});
  }
});
