import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, runTransaction, collection, query, where, getDocs, Timestamp, serverTimestamp, Bytes } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

const env = await initializeTestEnvironment({
  projectId: 'demo-edhi-pdf',
  firestore: { host: '127.0.0.1', port: 8085, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') },
});
const citizen = env.authenticatedContext('citizen', { email: '6110112345671@citizen.edhi.org' }).firestore();
const other = env.authenticatedContext('other').firestore();
const driver = env.authenticatedContext('driver').firestore();
const admin = env.authenticatedContext('admin').firestore();
let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log('PASS:', name); }
try {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, role] of [['other', 'user'], ['driver', 'employee'], ['admin', 'admin']]) {
      await setDoc(doc(db, 'users', uid), { role, isActive: true });
    }
    await setDoc(doc(db, 'employees', 'unit1'), { userId: 'driver', status: 'available', activeRequestId: '', isSimulated: false });
  });
  await test('Unauthenticated profiles are private', () => assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users', 'admin'))));
  await test('Registration and unique phone claim commit atomically', () => assertSucceeds(runTransaction(citizen, async (tx) => {
    const claim = doc(citizen, 'phone_claims', '+923001234567');
    await tx.get(claim);
    tx.set(claim, { userId: 'citizen' });
    tx.set(doc(citizen, 'users', 'citizen'), { role: 'user', isActive: true,
      cnic: '61101-1234567-1', phone: '+923001234567', authEmail: '6110112345671@citizen.edhi.org' });
  })));
  await test('Citizen cannot elevate role', () => assertFails(updateDoc(doc(citizen, 'users', 'citizen'), { role: 'admin' })));
  await test('Citizen cannot take another phone claim', () => assertFails(setDoc(doc(other, 'phone_claims', '+923001234567'), { userId: 'other' })));
  const aliasEmail = 'account_AbCdEfGhIjKlMnOpQrStUv@citizen.edhi.org';
  const aliasUser = env.authenticatedContext('alias-user', {email: aliasEmail}).firestore();
  const publicDb = env.unauthenticatedContext().firestore();
  await test('Free-plan phone and CNIC aliases register one private account atomically', () => assertSucceeds(runTransaction(aliasUser, async (tx) => {
    tx.set(doc(aliasUser, 'users', 'alias-user'), {role: 'user', isActive: true, cnic: '61101-2233445-1', phone: '+923112233445', authEmail: aliasEmail});
    tx.set(doc(aliasUser, 'phone_claims', '+923112233445'), {userId: 'alias-user'});
    tx.set(doc(aliasUser, 'login_aliases', 'cnic_6110122334451'), {authEmail: aliasEmail});
    tx.set(doc(aliasUser, 'login_aliases', 'phone_+923112233445'), {authEmail: aliasEmail});
  })));
  await test('Public username lookup returns only the opaque Auth identifier', async () => {
    const phone = await assertSucceeds(getDoc(doc(publicDb, 'login_aliases', 'phone_+923112233445')));
    const cnic = await assertSucceeds(getDoc(doc(publicDb, 'login_aliases', 'cnic_6110122334451')));
    assert.deepEqual(phone.data(), {authEmail: aliasEmail});
    assert.deepEqual(cnic.data(), phone.data());
    await assertFails(getDoc(doc(publicDb, 'users', 'alias-user')));
    await assertFails(getDocs(collection(publicDb, 'login_aliases')));
    await assertFails(getDocs(collection(aliasUser, 'login_aliases')));
  });
  await test('Username aliases cannot be stolen, redirected or used to publish personal fields', async () => {
    await assertFails(updateDoc(doc(aliasUser, 'login_aliases', 'phone_+923112233445'), {authEmail: 'attacker@citizen.edhi.org'}));
    await assertFails(setDoc(doc(other, 'login_aliases', 'phone_+923112233445'), {authEmail: aliasEmail}));
    await assertFails(setDoc(doc(aliasUser, 'login_aliases', 'phone_+923112233446'), {authEmail: aliasEmail}));
    await assertFails(setDoc(doc(publicDb, 'login_aliases', 'phone_+923112233446'), {authEmail: aliasEmail}));
    await assertFails(setDoc(doc(aliasUser, 'login_aliases', 'cnic_6110122334451'), {authEmail: aliasEmail, password: 'not-allowed'}));
  });
  await test('New opaque identity registration fails without both matching login aliases', async () => {
    const email = 'account_ZyXwVuTsRqPoNmLkJiHgFe@citizen.edhi.org';
    const partial = env.authenticatedContext('partial-alias', {email}).firestore();
    await assertFails(runTransaction(partial, async (tx) => {
      tx.set(doc(partial, 'users', 'partial-alias'), {role: 'user', isActive: true, cnic: '61101-3344556-1', phone: '+923113344556', authEmail: email});
      tx.set(doc(partial, 'phone_claims', '+923113344556'), {userId: 'partial-alias'});
    }));
  });
  const photoBytes = Bytes.fromUint8Array(Uint8Array.from([137, 80, 78, 71]));
  await test('Free-plan photos keep donation images private and missing-person images visible to active users', async () => {
    for (const kind of ['donations', 'missing_persons']) {
      await assertSucceeds(setDoc(doc(aliasUser, 'photo_attachments', kind), {userId: 'alias-user', kind, contentType: 'image/png', image: photoBytes, createdAt: serverTimestamp()}));
      await assertSucceeds(getDoc(doc(aliasUser, 'photo_attachments', kind)));
      await assertSucceeds(getDoc(doc(admin, 'photo_attachments', kind)));
      await assertFails(getDoc(doc(publicDb, 'photo_attachments', kind)));
    }
    await assertFails(getDoc(doc(other, 'photo_attachments', 'donations')));
    await assertSucceeds(getDoc(doc(other, 'photo_attachments', 'missing_persons')));
    await assertFails(getDocs(collection(aliasUser, 'photo_attachments')));
  });
  await test('Firestore photo validation rejects oversized images, spoofed owners and unsupported data', async () => {
    const photo = {userId: 'alias-user', kind: 'donations', contentType: 'image/png', image: photoBytes, createdAt: serverTimestamp()};
    for (const fields of [
      {userId: 'other'}, {kind: 'unknown'}, {contentType: 'text/plain'}, {image: 'not bytes'},
      {image: Bytes.fromUint8Array(new Uint8Array(256 * 1024 + 1))}, {password: 'not-allowed'},
    ]) await assertFails(setDoc(doc(aliasUser, 'photo_attachments', 'invalid-photo'), {...photo, ...fields}));
    await assertFails(updateDoc(doc(aliasUser, 'photo_attachments', 'donations'), {userId: 'other'}));
  });
  await test('Citizen creates pending request', () => assertSucceeds(setDoc(doc(citizen, 'emergency_requests', 'job1'),
    { userId: 'citizen', status: 'Pending', assignedEmployeeId: null, createdAt: serverTimestamp() })));
  await test('Other citizen cannot read patient request', () => assertFails(getDoc(doc(other, 'emergency_requests', 'job1'))));
  await test('Owner-filtered request query succeeds', () => assertSucceeds(getDocs(query(collection(citizen, 'emergency_requests'), where('userId', '==', 'citizen')))));
  await test('Admin assignment reserves unit atomically', () => assertSucceeds(runTransaction(admin, async (tx) => {
    tx.update(doc(admin, 'emergency_requests', 'job1'), { status: 'Assigned', assignedEmployeeId: 'unit1' });
    tx.update(doc(admin, 'employees', 'unit1'), { status: 'busy', activeRequestId: 'job1' });
  })));
  await test('Assigned driver can query only assigned jobs', () => assertSucceeds(getDocs(query(collection(driver, 'emergency_requests'), where('assignedEmployeeId', '==', 'unit1')))));
  await test('Driver cannot skip directly to completion', () => assertFails(updateDoc(doc(driver, 'emergency_requests', 'job1'), { status: 'Completed' })));
  await test('Driver cannot make busy unit available mid-response', () => assertFails(updateDoc(doc(driver, 'employees', 'unit1'), { status: 'available' })));
  await test('Driver GPS updates include a heartbeat and timestamp', async () => {
    await assertSucceeds(updateDoc(doc(driver, 'employees', 'unit1'), {
      currentLat: 34.1, currentLng: 73.2, transitLastHeartbeat: Date.now(), updatedAt: serverTimestamp(), locationUpdatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(other, 'employees', 'unit1'), { currentLat: 35 }));
  });
  await test('Driver stages proceed in order', async () => {
    await assertSucceeds(updateDoc(doc(driver, 'emergency_requests', 'job1'), { status: 'InProgress' }));
    await assertSucceeds(updateDoc(doc(driver, 'emergency_requests', 'job1'), { status: 'Arrived' }));
    await assertSucceeds(runTransaction(driver, async (tx) => {
      tx.update(doc(driver, 'emergency_requests', 'job1'), { status: 'Completed', updatedAt: serverTimestamp() });
      tx.update(doc(driver, 'employees', 'unit1'), { status: 'available', activeRequestId: '', speedKmh: 0 });
    }));
  });
  await test('Owner cancellation releases assigned unit atomically', async () => {
    await assertSucceeds(setDoc(doc(citizen, 'emergency_requests', 'job2'), { userId: 'citizen', status: 'Pending', assignedEmployeeId: null, createdAt: serverTimestamp() }));
    await assertSucceeds(runTransaction(admin, async (tx) => {
      tx.update(doc(admin, 'emergency_requests', 'job2'), { status: 'Assigned', assignedEmployeeId: 'unit1' });
      tx.update(doc(admin, 'employees', 'unit1'), { status: 'busy', activeRequestId: 'job2' });
    }));
    await assertSucceeds(runTransaction(citizen, async (tx) => {
      await tx.get(doc(citizen, 'route_demos', 'unit1'));
      tx.update(doc(citizen, 'emergency_requests', 'job2'), { status: 'Cancelled', updatedAt: serverTimestamp() });
      tx.set(doc(citizen, 'emergency_usage', 'citizen'), {
        cancellationCount: 1, windowStartedAt: serverTimestamp(), banStartedAt: null, lastCancelledRequestId: 'job2',
      });
      tx.update(doc(citizen, 'employees', 'unit1'), { status: 'available', activeRequestId: '', speedKmh: 0 });
    }));
    const released = (await getDoc(doc(admin, 'employees', 'unit1'))).data();
    assert.equal(released.activeRequestId, '');
    assert.equal(released.speedKmh, 0);
  });
  await test('Owner can cancel a moving ambulance inside one minute, stop its route and release it atomically', async () => {
    const uid = 'moving-citizen';
    const db = env.authenticatedContext(uid).firestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const seed = ctx.firestore();
      await setDoc(doc(seed, 'users', uid), {role: 'user', isActive: true});
      await setDoc(doc(seed, 'emergency_requests', 'moving-cancel'), {
        userId: uid, status: 'InProgress', assignedEmployeeId: 'cancel-unit',
        createdAt: Timestamp.fromMillis(Date.now() - 10000), updatedAt: Timestamp.now(),
      });
      await setDoc(doc(seed, 'employees', 'cancel-unit'), {
        userId: 'driver', status: 'busy', activeRequestId: 'moving-cancel', speedKmh: 30,
        currentLat: 34.2, currentLng: 73.23, isSimulated: true,
      });
      await setDoc(doc(seed, 'route_demos', 'cancel-unit'), {
        requestId: 'moving-cancel', userId: uid, driverUserId: 'driver', enabled: true,
        points: [{lat: 34.2, lng: 73.23}, {lat: 34.21, lng: 73.24}],
        startedAt: Timestamp.fromMillis(Date.now() - 5000), durationSeconds: 120,
        speedFactor: 1, simulation: true, stoppedAt: null, pausedAt: null,
      });
    });
    const cancel = (actor = db, extra = {}, release = true, stop = true) => runTransaction(actor, async (tx) => {
      await tx.get(doc(actor, 'route_demos', 'cancel-unit'));
      tx.update(doc(actor, 'emergency_requests', 'moving-cancel'), {status: 'Cancelled', updatedAt: serverTimestamp()});
      tx.set(doc(actor, 'emergency_usage', uid), {
        cancellationCount: 1, windowStartedAt: serverTimestamp(), banStartedAt: null, lastCancelledRequestId: 'moving-cancel',
      });
      if (release) tx.update(doc(actor, 'employees', 'cancel-unit'), {status: 'available', activeRequestId: '', speedKmh: 0, ...extra});
      if (stop) tx.update(doc(actor, 'route_demos', 'cancel-unit'), {enabled: false, stoppedAt: serverTimestamp()});
    });
    await assertFails(cancel(other));
    await assertFails(updateDoc(doc(db, 'employees', 'cancel-unit'), {status: 'available', activeRequestId: '', speedKmh: 0}));
    await assertFails(cancel(db, {currentLat: 35}));
    await assertFails(cancel(db, {}, false));
    await assertFails(cancel(db, {}, true, false));
    await assertSucceeds(cancel());
    const request = (await getDoc(doc(db, 'emergency_requests', 'moving-cancel'))).data();
    const unit = (await getDoc(doc(db, 'employees', 'cancel-unit'))).data();
    const route = (await getDoc(doc(db, 'route_demos', 'cancel-unit'))).data();
    assert.equal(request.status, 'Cancelled');
    assert.equal(unit.status, 'available');
    assert.equal(unit.activeRequestId, '');
    assert.equal(unit.speedKmh, 0);
    assert.equal(unit.currentLat, 34.2);
    assert.equal(route.enabled, false);
    assert.ok(route.stoppedAt.isEqual(request.updatedAt));
    await assertFails(cancel());
  });
  async function createRequest(id, db = citizen) {
    return setDoc(doc(db, 'emergency_requests', id), {
      userId: db === citizen ? 'citizen' : 'other', status: 'Pending', assignedEmployeeId: null, createdAt: serverTimestamp(),
    });
  }
  await test('Early arrival keeps the original one-minute cancellation window open', async () => {
    const uid = 'early-arrival';
    const db = env.authenticatedContext(uid).firestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const seed = ctx.firestore();
      await setDoc(doc(seed, 'users', uid), {role: 'user', isActive: true});
      await setDoc(doc(seed, 'emergency_requests', 'early-arrival-job'), {
        userId: uid, status: 'Arrived', assignedEmployeeId: 'early-arrival-unit', createdAt: Timestamp.now(),
      });
      await setDoc(doc(seed, 'employees', 'early-arrival-unit'), {
        userId: 'driver', status: 'busy', activeRequestId: 'early-arrival-job', speedKmh: 0,
      });
    });
    await assertSucceeds(runTransaction(db, async (tx) => {
      tx.update(doc(db, 'emergency_requests', 'early-arrival-job'), {status: 'Cancelled', updatedAt: serverTimestamp()});
      tx.set(doc(db, 'emergency_usage', uid), {
        cancellationCount: 1, windowStartedAt: serverTimestamp(), banStartedAt: null, lastCancelledRequestId: 'early-arrival-job',
      });
      tx.update(doc(db, 'employees', 'early-arrival-unit'), {status: 'available', activeRequestId: '', speedKmh: 0});
    }));
  });
  async function cancelRequest(id, count) {
    return runTransaction(citizen, async (tx) => {
      const usageRef = doc(citizen, 'emergency_usage', 'citizen');
      const previous = await tx.get(usageRef);
      tx.update(doc(citizen, 'emergency_requests', id), { status: 'Cancelled', updatedAt: serverTimestamp() });
      tx.set(usageRef, { cancellationCount: count,
        windowStartedAt: count === 1 ? serverTimestamp() : previous.data().windowStartedAt,
        banStartedAt: count === 3 ? serverTimestamp() : null, lastCancelledRequestId: id });
    });
  }
  await test('Cancellation cannot bypass or reset the counter', async () => {
    await createRequest('cancel2');
    await assertFails(updateDoc(doc(citizen, 'emergency_requests', 'cancel2'), { status: 'Cancelled', updatedAt: serverTimestamp() }));
    await assertFails(cancelRequest('cancel2', 1));
    await assertSucceeds(cancelRequest('cancel2', 2));
    await assertFails(cancelRequest('cancel2', 3));
    assert.equal((await getDoc(doc(citizen, 'emergency_usage', 'citizen'))).data().cancellationCount, 2);
    await assertFails(updateDoc(doc(citizen, 'emergency_usage', 'citizen'), { cancellationCount: 0 }));
    await assertFails(getDoc(doc(other, 'emergency_usage', 'citizen')));
  });
  await test('60-second deadline is enforced for pending, assigned and moving jobs without resetting on assignment', async () => {
    for (const status of ['Pending', 'Approved', 'Assigned', 'InProgress', 'Arrived']) {
      const id = `expired-${status}`;
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'emergency_requests', id), {
          userId: 'citizen', status, assignedEmployeeId: status === 'Pending' ? null : 'unit1',
          createdAt: Timestamp.fromMillis(Date.now() - 60000), updatedAt: Timestamp.now(),
        });
      });
      await assertFails(cancelRequest(id, 3));
    }
    await assertFails(setDoc(doc(citizen, 'emergency_requests', 'fake-clock'), {
      userId: 'citizen', status: 'Pending', assignedEmployeeId: null, createdAt: Timestamp.fromMillis(Date.now() + 60000),
    }));
  });
  await test('Closed requests cannot be cancelled within the first minute', async () => {
    for (const status of ['Completed', 'Cancelled']) {
      const id = `closed-${status}`;
      await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'emergency_requests', id), {
        userId: 'citizen', status, assignedEmployeeId: 'unit1', createdAt: Timestamp.now(),
      }));
      await assertFails(cancelRequest(id, 3));
    }
  });
  await test('Third cancellation blocks requests for 24 hours; other users unaffected', async () => {
    await createRequest('cancel3');
    await assertSucceeds(cancelRequest('cancel3', 3));
    const usage = (await getDoc(doc(citizen, 'emergency_usage', 'citizen'))).data();
    assert.ok(usage.banStartedAt instanceof Timestamp);
    await assertFails(createRequest('banned-job'));
    await assertSucceeds(createRequest('other-job', other));
  });
  await test('Ban automatically expires, then the cancellation window resets', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const old = Timestamp.fromMillis(Date.now() - 86401000);
      await setDoc(doc(ctx.firestore(), 'emergency_usage', 'citizen'), {
        cancellationCount: 3, windowStartedAt: old, banStartedAt: old, lastCancelledRequestId: 'cancel3',
      });
    });
    await assertSucceeds(createRequest('after-ban'));
    await assertSucceeds(cancelRequest('after-ban', 1));
    assert.equal((await getDoc(doc(citizen, 'emergency_usage', 'citizen'))).data().cancellationCount, 1);
  });
  await test('GPS rejects invalid coordinates and fake freshness timestamps', async () => {
    await assertFails(updateDoc(doc(driver, 'employees', 'unit1'), { currentLat: 91, currentLng: 73, locationUpdatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(driver, 'employees', 'unit1'), { currentLat: 34, currentLng: 73, locationUpdatedAt: Timestamp.fromMillis(Date.now() + 60000) }));
    await assertFails(updateDoc(doc(driver, 'employees', 'unit1'), { status: 'pretend-ready' }));
  });
  await test('Demo routes are admin-only and cannot overwrite live GPS', async () => {
    const demo = { requestId: 'job1', userId: 'citizen', driverUserId: 'driver', enabled: true, startedAt: serverTimestamp(), durationSeconds: 60,
      speedFactor: 1, points: [{ lat: 34.1, lng: 73.2 }, { lat: 34.2, lng: 73.3 }] };
    const gpsBefore = (await getDoc(doc(driver, 'employees', 'unit1'))).data();
    await assertFails(setDoc(doc(citizen, 'route_demos', 'unit1'), demo));
    await assertFails(setDoc(doc(driver, 'route_demos', 'unit1'), demo));
    await assertSucceeds(setDoc(doc(admin, 'route_demos', 'unit1'), demo));
    await assertSucceeds(getDoc(doc(citizen, 'route_demos', 'unit1')));
    assert.deepEqual((await getDoc(doc(driver, 'employees', 'unit1'))).data(), gpsBefore);
    await assertFails(getDoc(doc(other, 'route_demos', 'unit1')));
    await assertSucceeds(getDocs(query(collection(citizen, 'route_demos'), where('userId', '==', 'citizen'))));
    await assertSucceeds(updateDoc(doc(citizen, 'route_demos', 'unit1'), { enabled: false }));
    await assertSucceeds(updateDoc(doc(admin, 'route_demos', 'unit1'), { enabled: true }));
    await assertSucceeds(updateDoc(doc(driver, 'route_demos', 'unit1'), { enabled: false }));
  });
  await test('Admin can create an account-free simulated unit; citizens cannot', async () => {
    const unit = { userId: '', name: 'Virtual Driver', role: 'driver', status: 'available',
      vehicleNumber: 'SIM-001', currentLat: 34.2, currentLng: 73.23, isSimulated: true, activeRequestId: '' };
    await assertSucceeds(setDoc(doc(admin, 'employees', 'virtual-unit'), unit));
    await assertFails(setDoc(doc(citizen, 'employees', 'illegal-unit'), unit));
    assert.equal((await getDoc(doc(citizen, 'employees', 'virtual-unit'))).data().userId, '');
  });
  await test('Simulated units reject device GPS and citizen route controls', async () => {
    await assertSucceeds(setDoc(doc(admin, 'employees', 'sim-linked'), {
      userId: 'driver', role: 'driver', status: 'available', isSimulated: true, currentLat: 34.2, currentLng: 73.23,
    }));
    await assertFails(updateDoc(doc(driver, 'employees', 'sim-linked'), {
      currentLat: 34.21, currentLng: 73.24, locationUpdatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(citizen, 'route_demos', 'unit1'), { speedFactor: 10 }));
    await assertFails(updateDoc(doc(citizen, 'route_demos', 'unit1'), { pausedAt: serverTimestamp() }));
  });
  await test('Simulated assignment, pause, arrival and completion commit without driver login', async () => {
    // Request fixture only: normal requests are created by citizens, not admin.
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'emergency_requests', 'virtual-job'), {
      userId: 'citizen', status: 'Pending', assignedEmployeeId: null, createdAt: Timestamp.now(),
    }));
    await assertSucceeds(runTransaction(admin, async (tx) => {
      tx.update(doc(admin, 'emergency_requests', 'virtual-job'), { status: 'InProgress', assignedEmployeeId: 'virtual-unit', assignedDriverUserId: '', updatedAt: serverTimestamp() });
      tx.update(doc(admin, 'employees', 'virtual-unit'), { status: 'busy', activeRequestId: 'virtual-job' });
      tx.set(doc(admin, 'route_demos', 'virtual-unit'), { userId: 'citizen', driverUserId: '', requestId: 'virtual-job',
        points: [{lat: 34.2, lng: 73.23}, {lat: 34.21, lng: 73.24}], startedAt: serverTimestamp(),
        durationSeconds: 120, speedFactor: 1, enabled: true, pausedAt: null, stoppedAt: null, simulation: true });
    }));
    await assertSucceeds(getDoc(doc(citizen, 'route_demos', 'virtual-unit')));
    await assertFails(getDoc(doc(other, 'route_demos', 'virtual-unit')));
    await assertFails(updateDoc(doc(citizen, 'emergency_requests', 'virtual-job'), { status: 'Arrived' }));
    await assertSucceeds(updateDoc(doc(admin, 'route_demos', 'virtual-unit'), { pausedAt: serverTimestamp(), speedFactor: 10 }));
    await assertSucceeds(runTransaction(admin, async (tx) => {
      tx.update(doc(admin, 'emergency_requests', 'virtual-job'), {status: 'Arrived', updatedAt: serverTimestamp()});
      tx.update(doc(admin, 'employees', 'virtual-unit'), {currentLat: 34.21, currentLng: 73.24, speedKmh: 0});
      tx.update(doc(admin, 'route_demos', 'virtual-unit'), {enabled: false, stoppedAt: serverTimestamp()});
    }));
    assert.equal((await getDoc(doc(admin, 'employees', 'virtual-unit'))).data().status, 'busy');
    await assertSucceeds(runTransaction(admin, async (tx) => {
      tx.update(doc(admin, 'emergency_requests', 'virtual-job'), {status: 'Completed', updatedAt: serverTimestamp()});
      tx.update(doc(admin, 'employees', 'virtual-unit'), {status: 'available', activeRequestId: ''});
    }));
  });
  await test('Owner can freeze cancelled simulation only with a server timestamp', async () => {
    await assertSucceeds(updateDoc(doc(admin, 'route_demos', 'virtual-unit'), { enabled: true }));
    await assertFails(updateDoc(doc(citizen, 'route_demos', 'virtual-unit'), { enabled: false, stoppedAt: Timestamp.fromMillis(1) }));
    await assertSucceeds(updateDoc(doc(citizen, 'route_demos', 'virtual-unit'), { enabled: false, stoppedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(citizen, 'route_demos', 'virtual-unit'), { stoppedAt: serverTimestamp() }));
  });
  await test('Blood request cancellation belongs to requester', async () => {
    await assertSucceeds(setDoc(doc(citizen, 'blood_needs', 'blood1'), { userId: 'citizen', bloodGroup: 'O+', unitsNeeded: 2, status: 'active' }));
    await assertFails(updateDoc(doc(other, 'blood_needs', 'blood1'), { status: 'cancelled' }));
    await assertSucceeds(updateDoc(doc(citizen, 'blood_needs', 'blood1'), { status: 'cancelled', cancelledAt: Timestamp.now() }));
  });
  await test('All and specific-group donor queries both work', async () => {
    await assertSucceeds(setDoc(doc(citizen, 'blood_donors', 'donor1'), { userId: 'citizen', bloodGroup: 'O+' }));
    assert.equal((await getDocs(collection(citizen, 'blood_donors'))).size, 1);
    assert.equal((await getDocs(query(collection(citizen, 'blood_donors'), where('bloodGroup', '==', 'O+')))).size, 1);
  });
  await test('Missing report rejects future last-seen and permits owner status update', async () => {
    const report = { userId: 'citizen', age: 30, status: 'Searching', lastSeenAt: Timestamp.fromMillis(Date.now() - 60000) };
    await assertSucceeds(setDoc(doc(citizen, 'missing_persons', 'mp1'), report));
    await assertFails(setDoc(doc(citizen, 'missing_persons', 'future'), { ...report, lastSeenAt: Timestamp.fromMillis(Date.now() + 600000) }));
    await assertFails(updateDoc(doc(other, 'missing_persons', 'mp1'), { status: 'Found' }));
    await assertSucceeds(updateDoc(doc(citizen, 'missing_persons', 'mp1'), { status: 'Found' }));
  });
  await test('Photo upload requires ownership, image MIME type, and size limit', async () => {
    const storage = env.authenticatedContext('citizen').storage();
    await assertSucceeds(uploadBytes(ref(storage, 'missing_persons/citizen/photo1'), new Uint8Array([1, 2, 3]), { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(storage, 'missing_persons/other/photo1'), new Uint8Array([1]), { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(storage, 'missing_persons/citizen/not-image'), new Uint8Array([1]), { contentType: 'text/plain' }));
    await assertFails(uploadBytes(ref(storage, 'missing_persons/citizen/too-large'), new Uint8Array(5 * 1024 * 1024 + 1), { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), 'missing_persons/citizen/no-auth'), new Uint8Array([1]), { contentType: 'image/jpeg' }));
  });
  await test('Clothing donation photos are restricted to the donor and active admins', async () => {
    const ownerStorage = env.authenticatedContext('citizen').storage();
    const path = 'donations/citizen/clothing1';
    await assertSucceeds(uploadBytes(ref(ownerStorage, path), new Uint8Array([1, 2, 3]), {contentType: 'image/png'}));
    await assertSucceeds(getBytes(ref(ownerStorage, path)));
    await assertSucceeds(getBytes(ref(env.authenticatedContext('admin').storage(), path)));
    await assertFails(getBytes(ref(env.authenticatedContext('other').storage(), path)));
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), path)));
    await assertFails(uploadBytes(ref(ownerStorage, 'donations/other/photo1'), new Uint8Array([1]), {contentType: 'image/jpeg'}));
    await assertFails(uploadBytes(ref(ownerStorage, 'donations/citizen/not-image'), new Uint8Array([1]), {contentType: 'text/plain'}));
    await assertFails(uploadBytes(ref(ownerStorage, 'donations/citizen/empty'), new Uint8Array(), {contentType: 'image/jpeg'}));
    await assertFails(uploadBytes(ref(ownerStorage, 'donations/citizen/too-large'), new Uint8Array(5 * 1024 * 1024 + 1), {contentType: 'image/jpeg'}));
  });
  await test('Driver self-registration is atomic and cannot grant admin access', async () => {
    const newDriver = env.authenticatedContext('new-driver', {email: '6110177556681@citizen.edhi.org'}).firestore();
    await assertFails(setDoc(doc(newDriver, 'users', 'new-driver'), {role: 'admin', isActive: true}));
    await assertSucceeds(runTransaction(newDriver, async tx => {
      tx.set(doc(newDriver, 'phone_claims', '+923007755881'), {userId: 'new-driver'});
      tx.set(doc(newDriver, 'users', 'new-driver'), {role: 'employee', isActive: true, cnic: '61101-7755668-1', phone: '+923007755881', authEmail: '6110177556681@citizen.edhi.org'});
    }));
    await assertFails(setDoc(doc(newDriver, 'driver_links', 'new-driver'), {employeeId: 'virtual-unit'}));
    await assertFails(updateDoc(doc(newDriver, 'employees', 'virtual-unit'), {userId: 'new-driver'}));
    await assertFails(updateDoc(doc(newDriver, 'users', 'new-driver'), {role: 'admin'}));
  });
  await test('HQ creates an ambulance and driver claim atomically, and only admin can assign it', async () => {
    const unitRef = doc(admin, 'employees', 'hq-created-unit');
    const claimRef = doc(admin, 'driver_links', 'new-driver');
    await assertSucceeds(runTransaction(admin, async tx => {
      const unit = await tx.get(unitRef);
      const claim = await tx.get(claimRef);
      const profile = await tx.get(doc(admin, 'users', 'new-driver'));
      assert.equal(unit.exists(), false);
      assert.equal(claim.exists(), false);
      assert.equal(profile.data().role, 'employee');
      tx.set(unitRef, {userId: 'new-driver', name: 'Registered Driver', vehicleNumber: 'EDHI-HQ-01',
        status: 'available', activeRequestId: '', currentLat: 34.1986, currentLng: 73.2312, isSimulated: true});
      tx.set(claimRef, {employeeId: 'hq-created-unit', linkedAt: serverTimestamp()});
    }));
    const newDriver = env.authenticatedContext('new-driver').firestore();
    assert.equal((await getDoc(doc(newDriver, 'employees', 'hq-created-unit'))).data().userId, 'new-driver');
    assert.equal((await getDoc(doc(newDriver, 'driver_links', 'new-driver'))).data().employeeId, 'hq-created-unit');
    await assertFails(runTransaction(newDriver, async tx => {
      tx.set(doc(newDriver, 'employees', 'self-assigned-unit'), {userId: 'new-driver', status: 'available'});
      tx.set(doc(newDriver, 'driver_links', 'new-driver'), {employeeId: 'self-assigned-unit'});
    }));
    await assertFails(updateDoc(doc(citizen, 'employees', 'hq-created-unit'), {userId: 'citizen'}));
  });
  await test('Linked simulated driver completes only its arrived active job and releases the unit atomically', async () => {
    await assertSucceeds(setDoc(doc(admin, 'employees', 'driver-sim'), {userId: 'driver', isSimulated: true, status: 'busy', activeRequestId: 'driver-sim-job'}));
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'emergency_requests', 'driver-sim-job'), {userId: 'citizen', assignedEmployeeId: 'driver-sim', status: 'InProgress'});
    });
    await assertFails(updateDoc(doc(driver, 'emergency_requests', 'driver-sim-job'), {status: 'Arrived'}));
    await assertFails(updateDoc(doc(driver, 'emergency_requests', 'driver-sim-job'), {status: 'Completed'}));
    await assertSucceeds(updateDoc(doc(admin, 'emergency_requests', 'driver-sim-job'), {status: 'Arrived'}));
    await assertFails(updateDoc(doc(other, 'emergency_requests', 'driver-sim-job'), {status: 'Completed'}));
    await assertSucceeds(runTransaction(driver, async tx => {
      tx.update(doc(driver, 'emergency_requests', 'driver-sim-job'), {status: 'Completed', updatedAt: serverTimestamp()});
      tx.update(doc(driver, 'employees', 'driver-sim'), {status: 'available', activeRequestId: '', speedKmh: 0});
    }));
    assert.equal((await getDoc(doc(citizen, 'emergency_requests', 'driver-sim-job'))).data().status, 'Completed');
    assert.equal((await getDoc(doc(admin, 'employees', 'driver-sim'))).data().status, 'available');
    await assertFails(updateDoc(doc(driver, 'emergency_requests', 'driver-sim-job'), {status: 'Completed'}));
  });
  async function citizenCompletion(id = 'citizen-finish', db = citizen, extraUnitFields = {}) {
    return runTransaction(db, async tx => {
      tx.update(doc(db, 'emergency_requests', id), {status: 'Completed', updatedAt: serverTimestamp()});
      tx.update(doc(db, 'employees', 'citizen-unit'), {status: 'available', activeRequestId: '', speedKmh: 0, ...extraUnitFields});
    });
  }
  await test('Citizen cannot confirm before arrival, alter telemetry, or confirm another citizen’s job', async () => {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'employees', 'citizen-unit'), {userId: 'driver', isSimulated: true, status: 'busy', activeRequestId: 'citizen-finish', speedKmh: 20});
      await setDoc(doc(ctx.firestore(), 'emergency_requests', 'citizen-finish'), {userId: 'citizen', assignedEmployeeId: 'citizen-unit', status: 'InProgress'});
    });
    await assertFails(citizenCompletion());
    await assertSucceeds(updateDoc(doc(admin, 'emergency_requests', 'citizen-finish'), {status: 'Arrived'}));
    await assertFails(citizenCompletion('citizen-finish', other));
    await assertFails(citizenCompletion('citizen-finish', citizen, {currentLat: 12}));
    await assertFails(updateDoc(doc(citizen, 'emergency_requests', 'citizen-finish'), {status: 'Completed', updatedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(citizen, 'employees', 'citizen-unit'), {status: 'available', activeRequestId: '', speedKmh: 0}));
  });
  await test('Citizen confirmation completes the arrived job, clears responsibility and stops its route atomically', async () => {
    await assertSucceeds(setDoc(doc(admin, 'route_demos', 'citizen-unit'), {userId: 'citizen', driverUserId: 'driver', requestId: 'citizen-finish', enabled: true, simulation: true}));
    await assertSucceeds(runTransaction(citizen, async tx => {
      await tx.get(doc(citizen, 'emergency_requests', 'citizen-finish'));
      await tx.get(doc(citizen, 'employees', 'citizen-unit'));
      await tx.get(doc(citizen, 'route_demos', 'citizen-unit'));
      tx.update(doc(citizen, 'emergency_requests', 'citizen-finish'), {status: 'Completed', updatedAt: serverTimestamp()});
      tx.update(doc(citizen, 'employees', 'citizen-unit'), {status: 'available', activeRequestId: '', speedKmh: 0});
      tx.update(doc(citizen, 'route_demos', 'citizen-unit'), {enabled: false, stoppedAt: serverTimestamp()});
    }));
    assert.equal((await getDoc(doc(driver, 'emergency_requests', 'citizen-finish'))).data().status, 'Completed');
    const unit = (await getDoc(doc(citizen, 'employees', 'citizen-unit'))).data();
    assert.equal(unit.status, 'available');
    assert.equal(unit.activeRequestId, '');
    assert.equal(unit.speedKmh, 0);
    assert.equal((await getDoc(doc(citizen, 'route_demos', 'citizen-unit'))).data().enabled, false);
  });
  await test('Repeat confirmation and stale assignment cannot release another active response', async () => {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'emergency_requests', 'next-job'), {userId: 'other', assignedEmployeeId: 'citizen-unit', status: 'InProgress'});
    });
    await assertSucceeds(updateDoc(doc(admin, 'employees', 'citizen-unit'), {status: 'busy', activeRequestId: 'next-job'}));
    await assertFails(citizenCompletion());
    await assertSucceeds(updateDoc(doc(admin, 'emergency_requests', 'citizen-finish'), {status: 'Arrived'}));
    await assertFails(citizenCompletion());
    assert.equal((await getDoc(doc(citizen, 'employees', 'citizen-unit'))).data().activeRequestId, 'next-job');
    assert.equal((await getDoc(doc(citizen, 'employees', 'citizen-unit'))).data().status, 'busy');
  });
  console.log(`${passed} Firebase rules tests passed.`);
} finally { await env.cleanup(); }
