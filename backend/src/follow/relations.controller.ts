import { Request, Response } from 'express';
import prisma from '../utils/prisma';

const db = prisma as any;
type AuthReq = Request & { userId?: number };

const fail = (res: Response, status: number, message: string) =>
  res.status(status).json({ success: false, message });

const PUBLIC_FIELDS = {
  id: true,
  name: true,
  avatarUrl: true,
  avatarFrameUrl: true,
  displayId: true,
  level: true,
  vipLevel: true,
} as const;

/**
 * C16 — أصدقاء / أتابعه / يتابعني / الزوار.
 *
 * The follow rows already existed but nothing ever derived the four buckets the
 * client asked for, so the tabs "غير متفاعلة". The classification is a set
 * operation on accepted follows in both directions:
 *
 *   أصدقاء   = I follow them AND they follow me   → "صديق"      + إلغاء المتابعة
 *   أتابعه   = I follow them, no reply            → "تتابعه"    + إلغاء المتابعة
 *   يتابعني  = they follow me, I have not         → "يتابعك"    + رد المتابعة
 *
 * Returned in ONE response rather than three endpoints: the buckets are defined
 * by each other, so computing them separately lets the tabs disagree with
 * themselves while the user is looking at them.
 */
export const getRelations = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const [following, followers] = await Promise.all([
      db.follow.findMany({
        where: { followerId: userId, status: 'ACCEPTED' },
        select: { followingId: true, createdAt: true },
      }),
      db.follow.findMany({
        where: { followingId: userId, status: 'ACCEPTED' },
        select: { followerId: true, createdAt: true },
      }),
    ]);

    const followingIds = new Set<number>(following.map((f: any) => f.followingId));
    const followerIds = new Set<number>(followers.map((f: any) => f.followerId));

    const friendIds = [...followingIds].filter((id) => followerIds.has(id));
    const outgoingIds = [...followingIds].filter((id) => !followerIds.has(id));
    const incomingIds = [...followerIds].filter((id) => !followingIds.has(id));

    const allIds = [...new Set([...friendIds, ...outgoingIds, ...incomingIds])];
    const users = allIds.length
      ? await db.user.findMany({ where: { id: { in: allIds } }, select: PUBLIC_FIELDS })
      : [];
    const byId = new Map<number, any>(users.map((u: any) => [u.id, u]));
    const pick = (ids: number[]) => ids.map((id) => byId.get(id)).filter(Boolean);

    return res.json({
      success: true,
      data: {
        friends: pick(friendIds),
        following: pick(outgoingIds),
        followers: pick(incomingIds),
        counts: {
          friends: friendIds.length,
          following: outgoingIds.length,
          followers: incomingIds.length,
        },
      },
    });
  } catch (e) {
    console.error('[relations.getRelations]', e);
    return fail(res, 500, 'Server error');
  }
};

/** Dashboard key: minimum level required to SEE the الزوار tab. */
export const VISITORS_MIN_LEVEL_KEY = 'visitors_min_level';

export async function getVisitorsMinLevel(): Promise<number> {
  try {
    const row = await db.appSetting.findUnique({ where: { key: VISITORS_MIN_LEVEL_KEY } });
    const n = Number(row?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  } catch {
    return 0;
  }
}

export async function setVisitorsMinLevel(level: number): Promise<number> {
  const value = String(Math.max(0, Math.floor(level)));
  await db.appSetting.upsert({
    where: { key: VISITORS_MIN_LEVEL_KEY },
    update: { value },
    create: { key: VISITORS_MIN_LEVEL_KEY, value },
  });
  return Number(value);
}

/**
 * C16 — record a profile view. ONLY from the home page: the client was explicit
 * that opening someone from inside a room must not appear in الزوار
 * ("اللي دخلوا بروفايلي من الصفحه الرئيسيه مش من الغرفه"), so any other source
 * is accepted and discarded rather than rejected — the app should not have to
 * branch on it.
 *
 * Self-views never count, and a repeat view within the dedupe window updates
 * nothing: without that, one user idly reopening a profile floods the list and
 * buries everyone else.
 */
const VISIT_DEDUPE_MS = 60 * 60 * 1000;

export const recordProfileVisit = async (req: AuthReq, res: Response) => {
  try {
    const viewerId = req.userId;
    if (!viewerId) return fail(res, 401, 'Unauthorized');

    const profileId = Number(req.params.userId);
    if (!Number.isFinite(profileId) || profileId <= 0) return fail(res, 400, 'Invalid user id');
    if (profileId === viewerId) return res.json({ success: true, recorded: false });

    const source = String((req.body as any)?.source ?? 'home');
    if (source !== 'home') return res.json({ success: true, recorded: false });

    const recent = await db.profileVisit.findFirst({
      where: {
        profileId,
        viewerId,
        createdAt: { gte: new Date(Date.now() - VISIT_DEDUPE_MS) },
      },
      select: { id: true },
    });
    if (recent) return res.json({ success: true, recorded: false });

    await db.profileVisit.create({ data: { profileId, viewerId, source: 'home' } });
    return res.json({ success: true, recorded: true });
  } catch (e) {
    console.error('[relations.recordProfileVisit]', e);
    return fail(res, 500, 'Server error');
  }
};

/**
 * C16 — الزوار, newest first, with the timestamp the app renders as
 * date + time + ص/م. Gated on a level the admin sets from لوحة التحكم; below it
 * the tab is not merely empty but explicitly locked, so the app can say why.
 */
export const getMyVisitors = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const me = await db.user.findUnique({ where: { id: userId }, select: { level: true } });
    const minLevel = await getVisitorsMinLevel();
    if (minLevel > 0 && (me?.level ?? 1) < minLevel) {
      return res.json({
        success: true,
        locked: true,
        minLevel,
        message: `قائمة الزوار تظهر عند الوصول إلى المستوى ${minLevel}`,
        data: [],
      });
    }

    const limit = Math.min(200, Math.max(1, Math.floor(Number((req.query as any)?.limit) || 100)));
    const rows = await db.profileVisit.findMany({
      where: { profileId: userId },
      orderBy: { createdAt: 'desc' },
      take: limit,
      include: { viewer: { select: PUBLIC_FIELDS } },
    });

    return res.json({
      success: true,
      locked: false,
      minLevel,
      data: rows.map((r: any) => ({ visitedAt: r.createdAt, user: r.viewer })),
    });
  } catch (e) {
    console.error('[relations.getMyVisitors]', e);
    return fail(res, 500, 'Server error');
  }
};
