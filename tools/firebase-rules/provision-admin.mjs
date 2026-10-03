// Run locally after Firebase CLI sign-in. Never ship privileged credentials in the app.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const require = createRequire(import.meta.url);
const adminRequire = createRequire(new URL('../../functions/package.json', import.meta.url));
const {initializeApp, deleteApp} = adminRequire('firebase-admin/app');
const {getAuth} = adminRequire('firebase-admin/auth');
const cliAuth = require('firebase-tools/lib/auth');
const {CLOUD_PLATFORM, FIREBASE_PLATFORM} = require('firebase-tools/lib/scopes');
const workspace = fileURLToPath(new URL('../../', import.meta.url));
const projectId = 'eedhi-b08e1';
const email = 'admin@gmail.com';
const password = process.env.EDHI_ADMIN_PASSWORD;

async function main() {
  if (!password || password.length < 8) {
    throw new Error('Set EDHI_ADMIN_PASSWORD to the requested admin password before running.');
  }
  const projectConfig = JSON.parse(await readFile(resolve(workspace, '.firebaserc'), 'utf8'));
  if (projectConfig.projects?.default !== projectId) {
    throw new Error('Project configuration does not match eedhi-b08e1. No changes made.');
  }
  const account = cliAuth.getProjectDefaultAccount(workspace);
  if (!account?.tokens?.refresh_token) {
    throw new Error('Sign in with firebase login using an owner of eedhi-b08e1 first.');
  }
  async function accessToken() {
    return cliAuth.getAccessToken(account.tokens.refresh_token, [CLOUD_PLATFORM, FIREBASE_PLATFORM]);
  }
  async function api(url, {method = 'GET', body, allowMissing = false} = {}) {
    const token = await accessToken();
    const response = await fetch(url, {
      method,
      headers: {Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(30000),
    });
    if (allowMissing && response.status === 404) return null;
    const data = await response.json();
    if (!response.ok) throw new Error(`${response.status}: ${data.error?.message || 'Firebase request failed.'}`);
    return data;
  }
  const databaseUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`;
  // Check project access and database existence before creating any user.
  await api(databaseUrl);
  const configUrl = `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId}/config`;
  const config = await api(configUrl);
  if (!config.signIn?.email?.enabled) {
    await api(`${configUrl}?updateMask=signIn.email.enabled,signIn.email.passwordRequired`, {
      method: 'PATCH', body: {signIn: {email: {enabled: true, passwordRequired: true}}},
    });
  }

  const app = initializeApp({projectId, credential: {
    async getAccessToken() {
      const token = await accessToken();
      return {access_token: token.access_token, expires_in: token.expires_in || 3600};
    },
  }}, 'admin-hq-provisioning');
  const auth = getAuth(app);
  let user;
  let created = false;
  let profileSaved = false;
  try {
    try {
      user = await auth.getUserByEmail(email);
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      user = await auth.createUser({email, password, displayName: 'Admin HQ', disabled: true});
      created = true;
    }
    const profileUrl = `${databaseUrl}/documents/users/${encodeURIComponent(user.uid)}`;
    const existing = await api(profileUrl, {allowMissing: true});
    const fields = {
      id: {stringValue: user.uid},
      name: {stringValue: 'Admin HQ'},
      email: {stringValue: email},
      authEmail: {stringValue: email},
      role: {stringValue: 'admin'},
      isActive: {booleanValue: true},
    };
    if (!existing) Object.assign(fields, {
      phone: {stringValue: ''}, cnic: {stringValue: ''}, address: {stringValue: ''},
      profileImage: {stringValue: ''}, createdAt: {timestampValue: new Date().toISOString()},
    });
    const params = new URLSearchParams();
    for (const field of Object.keys(fields)) params.append('updateMask.fieldPaths', field);
    if (existing?.updateTime) params.set('currentDocument.updateTime', existing.updateTime);
    else params.set('currentDocument.exists', 'false');
    await api(`${profileUrl}?${params}`, {method: 'PATCH', body: {fields}});
    profileSaved = true;
    await auth.updateUser(user.uid, {password, displayName: 'Admin HQ', disabled: false});

    const verifiedUser = await auth.getUser(user.uid);
    const profile = await api(profileUrl);
    if (verifiedUser.email !== email || verifiedUser.disabled ||
        profile.fields.role?.stringValue !== 'admin' ||
        profile.fields.isActive?.booleanValue !== true) {
      throw new Error('Admin account verification failed.');
    }
    const googleServices = JSON.parse(await readFile(resolve(workspace, 'android/app/google-services.json'), 'utf8'));
    const apiKey = googleServices.client[0].api_key[0].current_key;
    const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({email, password, returnSecureToken: true}),
      signal: AbortSignal.timeout(30000),
    });
    const session = await response.json();
    if (!response.ok || session.localId !== user.uid) {
      throw new Error(`Admin password login verification failed: ${session.error?.message || response.status}`);
    }
    // Verify the app can read its role through the deployed client rules.
    const clientResponse = await fetch(profileUrl, {
      headers: {Authorization: `Bearer ${session.idToken}`}, signal: AbortSignal.timeout(30000),
    });
    const clientProfile = await clientResponse.json();
    if (!clientResponse.ok || clientProfile.fields?.role?.stringValue !== 'admin') {
      throw new Error('Admin credentials work, but client database rules still block the Admin HQ profile. Deploy firestore.rules.');
    }
    console.log(JSON.stringify({projectId, email, uid: user.uid, role: 'admin', isActive: true,
      passwordLoginVerified: true, clientProfileReadVerified: true}));
  } catch (error) {
    if (created && !profileSaved) {
      try { await auth.deleteUser(user.uid); }
      catch { console.error('New disabled Auth account needs cleanup because profile setup failed.'); }
    }
    throw error;
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
