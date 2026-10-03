export class PhoneLoginError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function normalizePhone(raw) {
  if (typeof raw !== 'string' || raw.length > 40 || /[a-z]/i.test(raw)) return '';
  let digits = raw.replace(/[^0-9]/g, '');
  if (digits.startsWith('0092')) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith('03')) digits = `92${digits.slice(1)}`;
  return /^923[0-9]{9}$/.test(digits) ? `+${digits}` : '';
}

// Identity resolution stays on the server. The client receives only a session token.
export function createPhoneLogin({limitAttempt, findAccount, signInWithPassword, verifyIdToken, createCustomToken}) {
  return async (body, ip) => {
    const phone = normalizePhone(body?.phone);
    const password = body?.password;
    if (!phone || typeof password !== 'string' || password.length < 6 || password.length > 4096) {
      throw new PhoneLoginError(400, 'Invalid phone number or password.');
    }
    await limitAttempt(phone, ip);
    const invalid = () => new PhoneLoginError(401, 'Invalid phone number or password.');
    const account = await findAccount(phone);
    if (!account || account.disabled || !account.email || !account.isActive ||
        !['user', 'employee', 'admin'].includes(account.role) || normalizePhone(account.phone) !== phone) {
      throw invalid();
    }
    let session;
    try {
      session = await signInWithPassword(account.email, password);
    } catch (error) {
      if (error instanceof PhoneLoginError) throw error;
      throw new PhoneLoginError(503, 'Phone sign-in is temporarily unavailable.');
    }
    if (!session?.idToken || session.localId !== account.uid) throw invalid();
    let verified;
    try { verified = await verifyIdToken(session.idToken); } catch (_) { throw invalid(); }
    if (verified.uid !== account.uid) throw invalid();
    return {token: await createCustomToken(account.uid)};
  };
}
