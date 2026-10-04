export function arrivalDeadline(route) {
  const started = route?.startedAt?.toMillis?.();
  const seconds = route?.durationSeconds;
  if (!Number.isFinite(started) || !Number.isFinite(seconds) || seconds < 0) return null;
  return started + Math.ceil(seconds * 1000) + 5000;
}

export function canCommitArrival({route, unit, job, employeeId, expected, now}) {
  const deadline = arrivalDeadline(route);
  const end = route?.points?.at(-1);
  return deadline !== null && now >= deadline && route.enabled === true
    && route.pausedAt == null && route.stoppedAt == null
    && route.requestId === expected.requestId
    && route.startedAt.toMillis() === expected.startedAtMs
    && route.durationSeconds === expected.durationSeconds
    && ['Assigned', 'InProgress'].includes(job?.status)
    && job.assignedEmployeeId === employeeId
    && unit?.status === 'busy' && unit.activeRequestId === route.requestId
    && Number.isFinite(end?.lat) && end.lat >= -90 && end.lat <= 90
    && Number.isFinite(end?.lng) && end.lng >= -180 && end.lng <= 180;
}
