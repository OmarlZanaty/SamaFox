import prisma from '../utils/prisma';

export const ROOM_SHARE_ORIGIN = 'https://samafox.almobarmg.com';
export const ANDROID_PACKAGE = 'com.almobarmg.samafox';
export const validShareToken = (token: unknown): token is string =>
  typeof token === 'string' && /^[A-Za-z0-9_-]{22,128}$/.test(token);
export const unavailable = { ok: false, code: 'ROOM_UNAVAILABLE', message: 'الغرفة غير متاحة حالياً' } as const;

// maxSeats is microphone capacity, NOT listener capacity. This schema has no
// listener limit, so there is intentionally no ROOM_FULL decision here.
export async function roomAdmission(roomId: number, userId: number, db = prisma) {
  const room = await db.room.findUnique({ where: { id: roomId } });
  if (!room?.isActive) return { room: null, error: unavailable };
  const ban = await db.roomBan.findUnique({ where: { roomId_userId: { roomId, userId } } });
  if (ban && (!ban.expiresAt || ban.expiresAt > new Date())) {
    return { room: null, error: { ok: false, code: 'BANNED', message: ban.reason || 'تم منعك من دخول هذه الغرفة' } };
  }
  return { room, error: null };
}

// Only a verified, unexpired token supplies attribution. It never grants entry.
export async function shareInviter(token: unknown, roomId: number): Promise<number | null> {
  if (!validShareToken(token)) return null;
  const share = await prisma.roomShareToken.findFirst({
    where: { token, roomId, revokedAt: null, expiresAt: { gt: new Date() } },
  });
  return share?.inviterId ?? null;
}

export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}

export function safePreviewUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value, ROOM_SHARE_ORIGIN);
    return url.protocol === 'https:' ? url.href : null;
  } catch { return null; }
}
