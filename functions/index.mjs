import {createHash} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, Timestamp} from 'firebase-admin/firestore';
import {onRequest} from 'firebase-functions/v2/https';
import {defineString} from 'firebase-functions/params';
import {createPhoneLogin, normalizePhone, PhoneLoginError} from './phone-login.mjs';

initializeApp();
const auth = getAuth();
const db = getFirestore();
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
