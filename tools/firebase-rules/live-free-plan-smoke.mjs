// Creates one temporary citizen to check the live free-plan configuration,
// then removes every test record and the temporary Authentication account.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomBytes, randomInt} from 'node:crypto';
import {createRequire} from 'node:module';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut, deleteUser} from 'firebase/auth';
import {getFirestore, doc, getDoc, runTransaction, setDoc, serverTimestamp, Bytes, terminate} from 'firebase/firestore';

const require = createRequire(import.meta.url);
const cliAuth = require('firebase-tools/lib/auth');
const scopes = require('firebase-tools/lib/scopes');
const config = JSON.parse(await readFile(new URL('../../android/app/google-services.json', import.meta.url), 'utf8'));
assert.equal(config.project_info.project_id, 'eedhi-b08e1');
const apiKey = config.client[0].api_key[0].current_key;
const projectId = config.project_info.project_id;
const app = initializeApp({projectId, apiKey, authDomain: `${projectId}.firebaseapp.com`, appId: config.client[0].client_info.mobilesdk_app_id}, 'live-free-plan-smoke');
const auth = getAuth(app);
const db = getFirestore(app);
const digits = `7${randomInt(100000, 999999)}${randomInt(100000, 999999)}`;
const cnic = `${digits.slice(0,5)}-${digits.slice(5,12)}-${digits.slice(12)}`;
const phone = `+92319${randomInt(1000000, 9999999)}`;
const authEmail = `account_${randomBytes(16).toString('base64url').toLowerCase()}@citizen.edhi.org`;
const password = randomBytes(24).toString('base64url');
const identityPaths = [`phone_claims/${phone}`, `login_aliases/cnic_${digits}`, `login_aliases/phone_${phone}`];
const paths = [];
let user;
let imagePath;
let success = false;
try {
  user = (await createUserWithEmailAndPassword(auth, authEmail, password)).user;
  await runTransaction(db, async (tx) => {
    const refs = identityPaths.map(path => doc(db, path));
    const existing = await Promise.all(refs.map(ref => tx.get(ref)));
    assert.ok(existing.every(snapshot => !snapshot.exists()));
    tx.set(doc(db, `users/${user.uid}`), {id: user.uid, name: 'Temporary verification citizen', email: '', authEmail, cnic, phone, role: 'user', isActive: true, createdAt: serverTimestamp()});
    tx.set(refs[0], {userId: user.uid});
    tx.set(refs[1], {authEmail});
    tx.set(refs[2], {authEmail});
  });
  paths.push(...identityPaths, `users/${user.uid}`);
  await signOut(auth);
  for (const key of [`phone_${phone}`, `cnic_${digits}`]) {
    const alias = (await getDoc(doc(db, 'login_aliases', key))).data();
    assert.deepEqual(Object.keys(alias), ['authEmail']);
    const session = await signInWithEmailAndPassword(auth, alias.authEmail, password);
    assert.equal(session.user.uid, user.uid);
    assert.equal((await getDoc(doc(db, 'users', user.uid))).data().role, 'user');
    await signOut(auth);
  }
  let rejected = false;
  try { await signInWithEmailAndPassword(auth, authEmail, 'incorrect-password'); }
  catch (error) { rejected = ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code); }
  assert.ok(rejected, 'Wrong password must be rejected by Firebase Authentication.');
  await signInWithEmailAndPassword(auth, authEmail, password);
  imagePath = `photo_attachments/verification_${randomBytes(8).toString('hex')}`;
  const image = Bytes.fromUint8Array(Uint8Array.from([137,80,78,71]));
  await setDoc(doc(db, imagePath), {userId: user.uid, kind: 'donations', contentType: 'image/png', image, createdAt: serverTimestamp()});
  paths.push(imagePath);
  assert.deepEqual((await getDoc(doc(db, imagePath))).data().image.toUint8Array(), image.toUint8Array());
  success = true;
} finally {
  const account = cliAuth.getProjectDefaultAccount(process.cwd());
  const token = await cliAuth.getAccessToken(account.tokens.refresh_token, [scopes.CLOUD_PLATFORM, scopes.FIREBASE_PLATFORM]);
  if (user) {
    for (const path of paths) {
      const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path.split('/').map(encodeURIComponent).join('/')}`, {
        method: 'DELETE', headers: {Authorization: `Bearer ${token.access_token}`}, signal: AbortSignal.timeout(30000),
      });
      assert.ok(response.ok || response.status === 404, `Cleanup failed for ${path}`);
    }
    await signInWithEmailAndPassword(auth, authEmail, password);
    await deleteUser(auth.currentUser);
  }
  await terminate(db);
  await deleteApp(app);
}
assert.ok(success);
console.log('PASS: Live phone and CNIC password login return the same UID; wrong password is denied; Firestore photo save/read succeeds; temporary account and records removed.');
