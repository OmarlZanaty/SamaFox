import crypto from 'crypto';
import prisma from '../utils/prisma';

/**
 * SPEC52 #37 — link a phone number to the CURRENT account (e.g. a Google one).
 *
 *   send-otp → 6-digit code, stored only as sha256(salt+code), 5 min, 5 tries,
 *              max 3 sends / 10 min per user and per number, 60 s cooldown.
 *   verify   → ONE serializable transaction: the number must not belong to
 *              another account → write user_auth_methods(phone) + users.phone.
 *              Never creates an account.
 *
 * SMS: Twilio Verify when TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN /
 * TWILIO_VERIFY_SERVICE_SID are set; otherwise, outside production, the code
 * is logged and returned as devCode; in production without a provider the
 * request is refused (503) rather than pretending a message was sent.
 */
export class PhoneLinkError extends Error {
  constructor(public status: number, message: string, public code = 'PHONE_LINK') {
    super(message);
  }
}

const COUNTRY_DIAL: Record<string, string> = { EG: '20', SA: '966', AE: '971', KW: '965', QA: '974', BH: '973', OM: '968', JO: '962', IQ: '964', LB: '961', SY: '963', YE: '967', LY: '218', TN: '216', DZ: '213', MA: '212', SD: '249', PS: '970' };

/** E.164 ("+201001234567"). Local numbers use the user's country (Egypt by default). */
export function normalizePhone(raw: string, countryCode?: string | null): string {
  let s = String(raw ?? '').replace(/[\s\-().]/g, '');
  // Arabic-Indic digits → ASCII
  s = s.replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
  if (s.startsWith('00')) s = '+' + s.slice(2);
  if (!s.startsWith('+')) {
    const dial = COUNTRY_DIAL[String(countryCode ?? 'EG').toUpperCase()] ?? '20';
    s = '+' + dial + s.replace(/^0+/, '');
  }
  if (!/^\+[1-9]\d{7,14}$/.test(s)) throw new PhoneLinkError(400, 'رقم الهاتف غير صالح', 'INVALID_PHONE');
  return s;
}

const hash = (salt: string, code: string) => crypto.createHash('sha256').update(salt + ':' + code).digest('hex');
const twilioReady = () =>
  !!(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_VERIFY_SERVICE_SID);

async function twilio(path: string, body: Record<string, string>) {
  const sid = process.env.TWILIO_ACCOUNT_SID!;
  const auth = Buffer.from(`${sid}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
  const r = await fetch(`https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SERVICE_SID}/${path}`, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body).toString(),
  });
  const j: any = await r.json().catch(() => ({}));
  if (!r.ok) throw new PhoneLinkError(502, 'تعذر إرسال رسالة التحقق، حاول لاحقاً', 'SMS_FAILED');
  return j;
}

async function assertNumberFree(db: any, userId: number, phone: string) {
  const [method, user] = await Promise.all([
    db.userAuthMethod.findFirst({ where: { phoneNumber: phone } }),
    db.user.findFirst({ where: { phone }, select: { id: true } }),
  ]);
  if ((method && method.userId !== userId) || (user && user.id !== userId)) {
    throw new PhoneLinkError(409, 'هذا الرقم مرتبط بحساب آخر.', 'PHONE_TAKEN');
  }
}

export async function sendPhoneOtp(userId: number, rawPhone: string) {
  const me = await prisma.user.findUnique({ where: { id: userId }, select: { countryCode: true } });
  const phone = normalizePhone(rawPhone, me?.countryCode);
  await assertNumberFree(prisma, userId, phone);

  const since = new Date(Date.now() - 10 * 60_000);
  const db = prisma as any;
  const [byUser, byPhone, last] = await Promise.all([
    db.phoneOtpChallenge.count({ where: { userId, createdAt: { gte: since } } }),
    db.phoneOtpChallenge.count({ where: { phoneNumber: phone, createdAt: { gte: since } } }),
    db.phoneOtpChallenge.findFirst({ where: { userId }, orderBy: { id: 'desc' } }),
  ]);
  if (last && Date.now() - new Date(last.createdAt).getTime() < 60_000) {
    throw new PhoneLinkError(429, 'انتظر دقيقة قبل طلب رمز جديد', 'OTP_COOLDOWN');
  }
  if (byUser >= 3 || byPhone >= 3) throw new PhoneLinkError(429, 'محاولات كثيرة، حاول بعد 10 دقائق', 'OTP_RATE');

  const production = process.env.NODE_ENV === 'production';
  if (!twilioReady() && production) {
    throw new PhoneLinkError(503, 'خدمة رسائل التحقق غير مفعّلة حالياً', 'SMS_DISABLED');
  }
  const salt = crypto.randomBytes(12).toString('hex');
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  let provider = 'local';
  let providerReference: string | null = null;
  if (twilioReady()) {
    const j = await twilio('Verifications', { To: phone, Channel: 'sms' });
    provider = 'twilio';
    providerReference = j?.sid ?? null;
  } else {
    console.log(`[phoneLink] DEV OTP for user ${userId} ${phone}: ${code}`);
  }
  await db.phoneOtpChallenge.create({
    data: {
      userId,
      phoneNumber: phone,
      codeHash: provider === 'local' ? hash(salt, code) : 'twilio',
      salt,
      provider,
      providerReference,
      expiresAt: new Date(Date.now() + 5 * 60_000),
    },
  });
  return { phone, expiresInSec: 300, resendInSec: 60, ...(provider === 'local' && !production ? { devCode: code } : {}) };
}

export async function verifyPhoneOtp(userId: number, rawPhone: string, code: string) {
  const me = await prisma.user.findUnique({ where: { id: userId }, select: { countryCode: true } });
  const phone = normalizePhone(rawPhone, me?.countryCode);
  const db = prisma as any;
  const ch = await db.phoneOtpChallenge.findFirst({
    where: { userId, phoneNumber: phone, consumedAt: null },
    orderBy: { id: 'desc' },
  });
  if (!ch || new Date(ch.expiresAt).getTime() < Date.now()) throw new PhoneLinkError(400, 'انتهت صلاحية الرمز، اطلب رمزاً جديداً', 'OTP_EXPIRED');
  if (ch.attempts >= 5) throw new PhoneLinkError(429, 'محاولات كثيرة، اطلب رمزاً جديداً', 'OTP_ATTEMPTS');

  let ok = false;
  if (ch.provider === 'twilio') {
    const j = await twilio('VerificationCheck', { To: phone, Code: String(code ?? '').trim() });
    ok = j?.status === 'approved';
  } else {
    const a = Buffer.from(hash(ch.salt, String(code ?? '').trim()));
    const b = Buffer.from(ch.codeHash);
    ok = a.length === b.length && crypto.timingSafeEqual(a, b);
  }
  if (!ok) {
    await db.phoneOtpChallenge.update({ where: { id: ch.id }, data: { attempts: { increment: 1 } } });
    throw new PhoneLinkError(400, 'الرمز غير صحيح', 'OTP_WRONG');
  }

  // Atomic link: a concurrent link of the same number by another account loses
  // on the unique phone index or the serializable re-check.
  try {
    return await prisma.$transaction(
      async (tx: any) => {
        const fresh = await tx.phoneOtpChallenge.updateMany({ where: { id: ch.id, consumedAt: null }, data: { consumedAt: new Date() } });
        if (!fresh.count) throw new PhoneLinkError(409, 'تم استخدام هذا الرمز بالفعل', 'OTP_USED');
        await assertNumberFree(tx, userId, phone);
        await tx.userAuthMethod.deleteMany({ where: { userId, provider: 'phone', NOT: { phoneNumber: phone } } });
        const existing = await tx.userAuthMethod.findFirst({ where: { userId, provider: 'phone', phoneNumber: phone } });
        if (!existing) {
          await tx.userAuthMethod.create({
            data: { userId, provider: 'phone', providerUserId: phone, phoneNumber: phone, verified: true },
          });
        }
        await tx.user.update({ where: { id: userId }, data: { phone } });
        return { phone, linked: true };
      },
      { isolationLevel: 'Serializable' },
    );
  } catch (e: any) {
    if (e instanceof PhoneLinkError) throw e;
    if (e?.code === 'P2002' || e?.code === 'P2034') throw new PhoneLinkError(409, 'هذا الرقم مرتبط بحساب آخر.', 'PHONE_TAKEN');
    throw e;
  }
}

export async function linkedPhone(userId: number) {
  const m = await (prisma as any).userAuthMethod.findFirst({
    where: { userId, provider: 'phone', verified: true },
    select: { phoneNumber: true, createdAt: true },
  });
  return m ? { phone: m.phoneNumber, linkedAt: m.createdAt } : null;
}
