// Read-only fleet diagnostic using the local Firebase CLI session.
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const require = createRequire(import.meta.url);
const auth = require('firebase-tools/lib/auth');
const {CLOUD_PLATFORM, FIREBASE_PLATFORM} = require('firebase-tools/lib/scopes');
const workspace = fileURLToPath(new URL('../../', import.meta.url));
const project = 'eedhi-b08e1';
const config = JSON.parse(await readFile(new URL('../../.firebaserc', import.meta.url), 'utf8'));
if (config.projects?.default !== project) throw new Error('Unexpected project.');
const account = auth.getProjectDefaultAccount(workspace);
if (!account?.tokens?.refresh_token) throw new Error('Firebase CLI sign-in required.');
const token = await auth.getAccessToken(account.tokens.refresh_token, [CLOUD_PLATFORM, FIREBASE_PLATFORM]);
async function readCollection(collection) {
  const docs = [];
  let pageToken = '';
  do {
    const url = new URL(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${collection}`);
    url.searchParams.set('pageSize', '100');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetch(url, {
      headers: {Authorization: `Bearer ${token.access_token}`},
      signal: AbortSignal.timeout(30000),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(`${response.status}: ${data.error?.message}`);
    docs.push(...(data.documents ?? []));
    pageToken = data.nextPageToken ?? '';
  } while (pageToken);
  return docs;
}
const [users, units, claims] = await Promise.all(['users', 'employees', 'driver_links'].map(readCollection));
const field = (doc, name) => doc.fields?.[name]?.stringValue ?? doc.fields?.[name]?.booleanValue ?? '';
console.log(JSON.stringify({
  project,
  registeredDrivers: users.filter(doc => field(doc, 'role') === 'employee').map(doc => ({
    id: doc.name.split('/').at(-1), name: field(doc, 'name'), active: field(doc, 'isActive'),
  })),
  ambulances: units.map(doc => ({id: doc.name.split('/').at(-1), driverUid: field(doc, 'userId'), plate: field(doc, 'vehicleNumber'), status: field(doc, 'status')})),
  driverLinks: claims.map(doc => ({uid: doc.name.split('/').at(-1), employeeId: field(doc, 'employeeId')})),
}, null, 2));
