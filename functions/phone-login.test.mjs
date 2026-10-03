import test from 'node:test';
import assert from 'node:assert/strict';
import {createPhoneLogin, normalizePhone, PhoneLoginError} from './phone-login.mjs';

const account = {uid: 'registered-uid', email: '6110112345671@citizen.edhi.org', phone: '+923001234567', role: 'user', isActive: true, disabled: false};
function setup(overrides = {}) {
  const calls = [];
  const login = createPhoneLogin({
    limitAttempt: async (phone, ip) => calls.push(['limit', phone, ip]),
    findAccount: async (phone) => { calls.push(['find', phone]); return account; },
    signInWithPassword: async (email, password) => {
      calls.push(['password', email, password]);
      if (password !== ' password123 ') throw new PhoneLoginError(401, 'Invalid phone number or password.');
      return {localId: account.uid, idToken: 'firebase-id-token'};
    },
    verifyIdToken: async (token) => { calls.push(['verify', token]); return {uid: account.uid}; },
    createCustomToken: async (uid) => { calls.push(['mint', uid]); return 'custom-token'; },
    ...overrides,
  });
  return {login, calls};
}

test('Equivalent Pakistani mobile formats resolve to one identity', () => {
  for (const value of ['0300-1234567', '+923001234567', '00923001234567', '923001234567']) assert.equal(normalizePhone(value), account.phone);
  for (const value of [null, {}, '', '0300', 'abc03001234567', '6110112345671']) assert.equal(normalizePhone(value), '');
});

test('Phone and password sign in as the existing UID and expose only a token', async () => {
  const {login, calls} = setup();
  assert.deepEqual(await login({phone: '03001234567', password: ' password123 '}, '127.0.0.1'), {token: 'custom-token'});
  assert.deepEqual(calls, [['limit', account.phone, '127.0.0.1'], ['find', account.phone], ['password', account.email, ' password123 '], ['verify', 'firebase-id-token'], ['mint', account.uid]]);
});

test('Malformed input cannot trigger an account lookup or token', async () => {
  for (const body of [null, {}, {phone: 'abc03001234567', password: 'password123'}, {phone: account.phone, password: ''}, {phone: account.phone, password: 'x'.repeat(4097)}]) {
    const {login, calls} = setup();
    await assert.rejects(login(body, 'ip'), (error) => error.status === 400);
    assert.deepEqual(calls, []);
  }
});

test('Unknown phone and wrong password return the same generic error', async () => {
  const missing = setup({findAccount: async () => null});
  const wrong = setup();
  for (const {login, calls} of [missing, wrong]) {
    await assert.rejects(login({phone: account.phone, password: 'wrong-password'}, 'ip'), (error) => error.status === 401 && error.message === 'Invalid phone number or password.');
    assert.equal(calls.some(([action]) => action === 'mint'), false);
  }
});

test('Disabled, inactive, mismatched and invalid-role accounts cannot sign in', async () => {
  for (const profile of [{...account, disabled: true}, {...account, isActive: false}, {...account, role: 'superuser'}, {...account, phone: '+923001234568'}, {...account, email: ''}]) {
    const {login, calls} = setup({findAccount: async () => profile});
    await assert.rejects(login({phone: account.phone, password: ' password123 '}, 'ip'), (error) => error.status === 401);
    assert.equal(calls.some(([action]) => action === 'password' || action === 'mint'), false);
  }
});

test('Password responses must match the resolved account UID', async () => {
  const {login, calls} = setup({signInWithPassword: async () => ({localId: 'other-user', idToken: 'token'})});
  await assert.rejects(login({phone: account.phone, password: ' password123 '}, 'ip'), (error) => error.status === 401);
  assert.equal(calls.some(([action]) => action === 'mint'), false);
});

test('Invalid or wrong-project ID tokens cannot mint a session', async () => {
  for (const verifyIdToken of [async () => ({uid: 'other-user'}), async () => { throw new Error('wrong audience'); }]) {
    const {login, calls} = setup({verifyIdToken});
    await assert.rejects(login({phone: account.phone, password: ' password123 '}, 'ip'), (error) => error.status === 401);
    assert.equal(calls.some(([action]) => action === 'mint'), false);
  }
});

test('Rate limits stop account lookup and password verification', async () => {
  const {login, calls} = setup({limitAttempt: async () => { throw new PhoneLoginError(429, 'Too many attempts. Please wait and retry.'); }});
  await assert.rejects(login({phone: account.phone, password: ' password123 '}, 'ip'), (error) => error.status === 429);
  assert.deepEqual(calls, []);
});

test('Firebase network failures are retryable and never mint a session', async () => {
  const {login, calls} = setup({signInWithPassword: async () => { throw new Error('network error'); }});
  await assert.rejects(login({phone: account.phone, password: ' password123 '}, 'ip'), (error) => error.status === 503);
  assert.equal(calls.some(([action]) => action === 'mint'), false);
});
