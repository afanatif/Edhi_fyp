import {test} from 'node:test';
import assert from 'node:assert/strict';
import {arrivalDeadline, canCommitArrival} from './arrival-policy.mjs';
const route = {requestId: 'job', startedAt: {toMillis: () => 1000}, durationSeconds: 10.0005,
  points: [{lat: 34.2, lng: 73.2}], enabled: true, pausedAt: null, stoppedAt: null};
const fixture = {route, job: {status: 'InProgress', assignedEmployeeId: 'unit'},
  unit: {status: 'busy', activeRequestId: 'job'}, employeeId: 'unit',
  expected: {requestId: 'job', startedAtMs: 1000, durationSeconds: 10.0005}, now: 16001};
test('Deadline includes five real seconds and rounds fractional travel up', () => {
  assert.equal(arrivalDeadline(route), 16001);
  assert.equal(canCommitArrival({...fixture, now: 16000}), false);
  assert.equal(canCommitArrival(fixture), true);
});
test('Paused, stopped, cancelled, completed or replaced missions cannot arrive', () => {
  for (const patch of [{enabled: false}, {pausedAt: {}}, {stoppedAt: {}}, {requestId: 'new'},
    {durationSeconds: 9}, {startedAt: {toMillis: () => 999}}, {points: []}]) {
    assert.equal(canCommitArrival({...fixture, route: {...route, ...patch}}), false);
  }
  for (const status of ['Arrived', 'Completed', 'Cancelled', 'Pending']) {
    assert.equal(canCommitArrival({...fixture, job: {...fixture.job, status}}), false);
  }
  assert.equal(canCommitArrival({...fixture, unit: {...fixture.unit, activeRequestId: 'another'}}), false);
  assert.equal(canCommitArrival({...fixture, employeeId: 'other-unit'}), false);
});
test('Corrupt timestamps, durations and coordinates fail closed', () => {
  for (const patch of [{startedAt: null}, {durationSeconds: NaN}, {durationSeconds: -1},
    {points: [{lat: 120, lng: 73}]}]) {
    assert.equal(canCommitArrival({...fixture, route: {...route, ...patch}}), false);
  }
});
