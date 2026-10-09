import { Router, type Request, type Response } from 'express';
import prisma from '../utils/prisma';
import { requireSuperAdmin } from '../middlewares/adminDashboard.middleware';
import { AUDIT_ACTIONS, auditContext, recordAdminAudit } from '../services/adminAudit.service';
import { GameSettingsError, KNOWN_GAMES, getGameSettings, setGameSettings } from '../services/gameConfig.service';
import { auditLog, fundGamePool, fundLuckyPool, gameEconomyReport, luckyLog, luckyReport, parseRange } from '../services/economyAdmin.service';
import {
  LUCKY_CONFIG_KEY,
  LUCKY_MULTIPLIERS,
  analyzeTiers,
  getLuckyConfig,
  invalidateLuckyCache,
  validateLuckyConfig,
  validateTiers,
  type LuckyConfig,
} from '../gifts/lucky.service';
import { getCustomFee, getGlobalBreakFees, setGlobalBreakFees, upsertCustomFee } from '../services/cpBreak.service';
import { invalidateCpEffectsCache } from '../services/cpEffect.service';
import { computeCpLevel, readCpSettings } from '../services/cpUnlock.service';
import { FEATURE_CATALOG, FeatureError, grantFeature, isFeatureKey, listUserFeaturesAdmin, revokeFeature } from '../services/features.service';
import { TargetError, cancelHostTarget, getHostTargetView, listHostTargets, setHostTarget } from '../services/hostTarget.service';
import { MAX_ROOM_PINS, ROOM_PIN_KEY, getRoomPins, invalidateRoomPins, parsePins, rankedRoomIds, resolvePinRanks } from '../services/roomRanking.service';
import { FEATURED_ROOM_ID } from '../controllers/room.controller';
import { buildTargetBalance } from '../agencies/agency.controller';

const db = prisma as any;

/**
 * لوحة التحكم — 2026-09-26 pages. Mounted inside the dashboard router, so
 * every request has already passed `authenticate` + `requireAdminDashboard`.
 * Changes that move money or odds, and permission grants, additionally need a
 * super admin and a written reason; every change writes admin_audit_logs with
 * the admin, the before/after values, the reason, the IP and the session.
 *
 *   /games-economy            GET report · PATCH /:game settings · POST /:game/fund
 *   /lucky-mgmt               GET summary · PATCH /settings · PUT /tiers · GET /log · POST /fund
 *   /cp-economy               break fees (global + custom per ID), levels, effects, break log
 *   /features                 «منح المميزات»: user lookup, grant / revoke, hidden entries
 *   /host-targets             the one source of Target المضيف
 *   /rooms-mgmt               room type (OFFICIAL_ROOM) and hidden-entry allowance
 *   /room-order               ترتيب الغرف: pinned IDs first, then most people now
 *   /audit-log                every admin action, filterable
 */
export const adminEconomyRouter = Router();
const r = adminEconomyRouter;

const adminId = (req: Request) => Number((req as any).userId);
const ok = (res: Response, data: unknown) =>
  res.json(JSON.parse(JSON.stringify({ success: true, data }, (_k, v) => (typeof v === 'bigint' ? v.toString() : v))));
const bad = (res: Response, status: number, message: string, code?: string) =>
  res.status(status).json({ success: false, code, message });

function needReason(req: Request, res: Response): string | null {
  const reason = String((req.body as any)?.reason ?? '').trim();
  if (reason.length < 3) {
    bad(res, 400, 'اكتب سبب التعديل (يُحفظ في سجل المراجعة)', 'REASON_REQUIRED');
    return null;
  }
  return reason;
}

const intOrNull = (v: unknown) => {
  if (v === null || v === '' || v === undefined) return null;
  const n = Math.floor(Number(v));
  return Number.isFinite(n) ? n : NaN;
};

async function userCard(raw: unknown) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  const select = {
    id: true, name: true, displayId: true, avatarUrl: true, coinsBalance: true,
    isBanned: true, banExpiresAt: true, isAdmin: true, isSuperAdmin: true, level: true, vipLevel: true, createdAt: true,
  };
  const u = (await db.user.findUnique({ where: { displayId: n }, select })) ?? (await db.user.findUnique({ where: { id: n }, select }));
  if (!u) return null;
  const banned = u.isBanned && (!u.banExpiresAt || new Date(u.banExpiresAt) > new Date());
  return { ...u, accountStatus: banned ? 'BANNED' : 'ACTIVE' };
}

// ════════════════════════ إدارة اقتصاد الألعاب ════════════════════════

r.get('/games-economy', async (req, res) => {
  try {
    const { from, to } = parseRange(req.query.from, req.query.to);
    return ok(res, await gameEconomyReport(from, to));
  } catch (e) {
    console.error('[admin.games-economy]', e);
    return bad(res, 500, 'Server error');
  }
});

r.patch('/games-economy/:game', requireSuperAdmin, async (req, res) => {
  try {
    const game = String(req.params.game);
    if (!(KNOWN_GAMES as readonly string[]).includes(game)) return bad(res, 404, 'Unknown game');
    const reason = needReason(req, res);
    if (!reason) return;
    const b = req.body ?? {};
    const patch: Record<string, unknown> = {};
    if (b.enabled != null) patch.enabled = Boolean(b.enabled);
    for (const f of ['minBet', 'maxBet', 'maxWinPerRound', 'dailyMaxWinPerUser', 'maxPayoutRatio', 'rtpTargetBp', 'broadcastMinX'] as const) {
      if (b[f] === undefined) continue;
      const v = intOrNull(b[f]);
      if (Number.isNaN(v)) return bad(res, 400, `${f}: رقم غير صالح`);
      patch[f] = v;
    }
    if (b.programShareBp !== undefined) {
      const v = intOrNull(b.programShareBp);
      if (v == null || Number.isNaN(v)) return bad(res, 400, 'programShareBp: رقم غير صالح');
      patch.programShareBp = v;
    }
    if (!Object.keys(patch).length) return bad(res, 400, 'nothing to update');
    const before = await getGameSettings(game);
    const after = await setGameSettings(game, patch as any);
    await recordAdminAudit({
      adminId: adminId(req),
      action: 'rtpTargetBp' in patch || 'maxPayoutRatio' in patch ? AUDIT_ACTIONS.GAME_PROBABILITY_UPDATE : AUDIT_ACTIONS.GAME_ECONOMY_UPDATE,
      targetType: 'game',
      targetId: game,
      before,
      after,
      ...auditContext(req),
      reason,
    });
    return ok(res, { game, settings: after });
  } catch (e) {
    if (e instanceof GameSettingsError) return bad(res, 400, e.message, 'INVALID_SETTINGS');
    console.error('[admin.games-economy.patch]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/games-economy/:game/fund', requireSuperAdmin, async (req, res) => {
  try {
    const game = String(req.params.game);
    if (!(KNOWN_GAMES as readonly string[]).includes(game)) return bad(res, 404, 'Unknown game');
    const reason = needReason(req, res);
    if (!reason) return;
    const amount = Math.floor(Number(req.body?.amount));
    if (!Number.isFinite(amount) || amount <= 0 || amount > 1_000_000_000) return bad(res, 400, 'المبلغ غير صالح');
    const out = await fundGamePool(game, amount, adminId(req));
    await recordAdminAudit({
      adminId: adminId(req),
      action: AUDIT_ACTIONS.GAME_POOL_FUND,
      targetType: 'game_pool',
      targetId: game,
      before: { poolBalance: out.poolBalance - amount },
      after: { poolBalance: out.poolBalance, funded: amount },
      ...auditContext(req),
      reason,
    });
    return ok(res, out);
  } catch (e) {
    console.error('[admin.games-economy.fund]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ Lucky Management ════════════════════════

r.get('/lucky-mgmt', async (req, res) => {
  try {
    const { from, to } = parseRange(req.query.from, req.query.to);
    const [config, tiers, pool, report] = await Promise.all([
      getLuckyConfig(),
      db.luckyTier.findMany({ orderBy: { multiplier: 'asc' } }),
      db.luckyPool.findUnique({ where: { id: 1 } }),
      luckyReport(from, to),
    ]);
    const active = tiers.filter((t: any) => t.isActive);
    return ok(res, {
      config,
      multipliers: LUCKY_MULTIPLIERS,
      tiers,
      analysis: analyzeTiers(active, config.hostShareBp, config),
      pool,
      report,
    });
  } catch (e) {
    console.error('[admin.lucky-mgmt]', e);
    return bad(res, 500, 'Server error');
  }
});

r.patch('/lucky-mgmt/settings', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const before = await getLuckyConfig();
    const b = req.body ?? {};
    const next: LuckyConfig = { ...before };
    for (const f of ['programShareBp', 'prizePoolBp', 'hostShareBp', 'minPlayers', 'maxPlayers', 'minEntry', 'maxEntry', 'rtpTargetBp', 'maxWin', 'roundSeconds', 'broadcastMin', 'poolFloor'] as const) {
      if (b[f] === undefined) continue;
      const v = Number(b[f]);
      if (!Number.isFinite(v)) return bad(res, 400, `${f}: رقم غير صالح`);
      (next as any)[f] = Math.floor(v);
    }
    if (b.enabled != null) next.enabled = Boolean(b.enabled);
    const invalid = validateLuckyConfig(next);
    if (invalid) return bad(res, 400, invalid, 'INVALID_SETTINGS');
    // The live tier table must still fit the new settings.
    const active = await db.luckyTier.findMany({ where: { isActive: true } });
    const tierProblem = validateTiers(active, next);
    if (tierProblem) return bad(res, 400, `جدول الاحتمالات الحالي لا يناسب الإعدادات الجديدة: ${tierProblem}`, 'INVALID_TIERS');
    const value = JSON.stringify(next);
    await db.$transaction(async (tx: any) => {
      await tx.appSetting.upsert({ where: { key: LUCKY_CONFIG_KEY }, update: { value }, create: { key: LUCKY_CONFIG_KEY, value } });
      await recordAdminAudit(
        { adminId: adminId(req), action: AUDIT_ACTIONS.LUCKY_SETTINGS_UPDATE, targetType: 'lucky', targetId: 'config', before, after: next, ...auditContext(req), reason },
        tx,
      );
    });
    invalidateLuckyCache();
    return ok(res, { config: next });
  } catch (e) {
    console.error('[admin.lucky-mgmt.settings]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/lucky-mgmt/tiers', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const input = Array.isArray(req.body?.tiers) ? req.body.tiers : null;
    if (!input) return bad(res, 400, 'tiers[] required');
    const rows = input.map((t: any) => ({
      multiplier: Math.floor(Number(t.multiplier)),
      weightBp: Math.floor(Number(t.weightBp)),
      minPoolCoins: BigInt(Math.max(0, Math.floor(Number(t.minPoolCoins ?? 0)))),
      isActive: t.isActive !== false,
    }));
    const cfg = await getLuckyConfig();
    const problem = validateTiers(rows.filter((t: any) => t.isActive), cfg);
    if (problem) return bad(res, 400, problem, 'INVALID_TIERS');
    const before = await db.luckyTier.findMany({ orderBy: { multiplier: 'asc' } });
    await db.$transaction(async (tx: any) => {
      for (const t of rows) {
        await tx.luckyTier.upsert({
          where: { multiplier: t.multiplier },
          update: { weightBp: t.weightBp, minPoolCoins: t.minPoolCoins, isActive: t.isActive },
          create: t,
        });
      }
      await recordAdminAudit(
        {
          adminId: adminId(req),
          action: AUDIT_ACTIONS.LUCKY_TIERS_UPDATE,
          targetType: 'lucky',
          targetId: 'tiers',
          before: before.map((t: any) => ({ multiplier: t.multiplier, weightBp: t.weightBp, minPoolCoins: String(t.minPoolCoins), isActive: t.isActive })),
          after: rows.map((t: any) => ({ ...t, minPoolCoins: String(t.minPoolCoins) })),
          ...auditContext(req),
          reason,
        },
        tx,
      );
    });
    invalidateLuckyCache();
    const tiers = await db.luckyTier.findMany({ orderBy: { multiplier: 'asc' } });
    return ok(res, { tiers, analysis: analyzeTiers(tiers.filter((t: any) => t.isActive), cfg.hostShareBp, cfg) });
  } catch (e) {
    console.error('[admin.lucky-mgmt.tiers]', e);
    return bad(res, 500, 'Server error');
  }
});

r.get('/lucky-mgmt/log', async (req, res) => {
  try {
    let userId: number | null = null;
    if (req.query.user) {
      const u = await userCard(req.query.user);
      if (!u) return ok(res, { total: 0, page: 1, pageSize: 50, rows: [] });
      userId = u.id;
    }
    const from = req.query.from ? new Date(String(req.query.from)) : null;
    const to = req.query.to ? new Date(String(req.query.to)) : null;
    return ok(
      res,
      await luckyLog({
        userId,
        roomId: req.query.room ? Number(req.query.room) || null : null,
        roundCode: req.query.round ? String(req.query.round) : null,
        from: from && Number.isFinite(from.getTime()) ? from : null,
        to: to && Number.isFinite(to.getTime()) ? to : null,
        page: Number(req.query.page) || 1,
      }),
    );
  } catch (e) {
    console.error('[admin.lucky-mgmt.log]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/lucky-mgmt/fund', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const amount = Math.floor(Number(req.body?.amount));
    if (!Number.isFinite(amount) || amount <= 0 || amount > 1_000_000_000) return bad(res, 400, 'المبلغ غير صالح');
    const out = await fundLuckyPool(amount, adminId(req));
    await recordAdminAudit({
      adminId: adminId(req),
      action: AUDIT_ACTIONS.LUCKY_POOL_FUND,
      targetType: 'lucky_pool',
      targetId: '1',
      before: { poolBalance: out.poolBalance - amount },
      after: { poolBalance: out.poolBalance, funded: amount },
      ...auditContext(req),
      reason,
    });
    return ok(res, out);
  } catch (e) {
    console.error('[admin.lucky-mgmt.fund]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ CP: fees, levels, effects ════════════════════════

r.get('/cp-economy/break-fees', async (_req, res) => {
  try {
    return ok(res, await getGlobalBreakFees());
  } catch (e) {
    console.error('[admin.cp.break-fees]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/cp-economy/break-fees', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const p = Math.floor(Number(req.body?.programFee));
    const q = Math.floor(Number(req.body?.partnerFee));
    if (!Number.isFinite(p) || p < 0 || !Number.isFinite(q) || q < 0) return bad(res, 400, 'الرسوم يجب أن تكون صفر أو أكثر');
    const before = await getGlobalBreakFees();
    const after = await db.$transaction(async (tx: any) => {
      const out = await setGlobalBreakFees(p, q, tx);
      await recordAdminAudit(
        { adminId: adminId(req), action: AUDIT_ACTIONS.CP_BREAK_FEE_UPDATE, targetType: 'setting', targetId: 'cp_break_fee', before, after: out, ...auditContext(req), reason },
        tx,
      );
      return out;
    });
    return ok(res, after);
  } catch (e) {
    console.error('[admin.cp.break-fees.put]', e);
    return bad(res, 500, 'Server error');
  }
});

r.get('/cp-economy/custom-fee/:user', async (req, res) => {
  try {
    const u = await userCard(req.params.user);
    if (!u) return bad(res, 404, 'لا يوجد مستخدم بهذا الرقم');
    const [custom, pairs, cfg, global] = await Promise.all([
      getCustomFee(u.id),
      db.cpPair.findMany({
        where: { OR: [{ userAId: u.id }, { userBId: u.id }] },
        include: {
          userA: { select: { id: true, name: true, displayId: true, avatarUrl: true } },
          userB: { select: { id: true, name: true, displayId: true, avatarUrl: true } },
        },
      }),
      readCpSettings(),
      getGlobalBreakFees(),
    ]);
    return ok(res, {
      user: u,
      custom,
      global,
      partners: pairs.map((p: any) => ({
        pairId: p.id,
        partner: p.userAId === u.id ? p.userB : p.userA,
        since: p.createdAt,
        cpValue: p.cpValue,
        level: computeCpLevel({ cpValue: p.cpValue, createdAt: p.createdAt, levelOverride: p.levelOverride }, cfg).level,
      })),
    });
  } catch (e) {
    console.error('[admin.cp.custom-fee.get]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/cp-economy/custom-fee/:userId', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const userId = Number(req.params.userId);
    const u = await db.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!u) return bad(res, 404, 'المستخدم غير موجود');
    const p = Math.floor(Number(req.body?.programFee));
    const q = Math.floor(Number(req.body?.partnerFee));
    if (!Number.isFinite(p) || p < 0 || !Number.isFinite(q) || q < 0) return bad(res, 400, 'الرسوم يجب أن تكون صفر أو أكثر');
    const before = await getCustomFee(userId);
    const row = await db.$transaction(async (tx: any) => {
      const out = await upsertCustomFee(userId, { programFee: p, partnerFee: q, enabled: req.body?.enabled !== false, note: req.body?.note ?? null }, adminId(req), tx);
      await recordAdminAudit(
        {
          adminId: adminId(req),
          action: AUDIT_ACTIONS.CP_BREAK_CUSTOM_FEE,
          targetUserId: userId,
          targetType: 'cp_break_custom_fee',
          targetId: userId,
          before: before ? { programFee: String(before.programFee), partnerFee: String(before.partnerFee), enabled: before.enabled } : null,
          after: { programFee: p, partnerFee: q, enabled: out.enabled },
          ...auditContext(req),
          reason,
        },
        tx,
      );
      return out;
    });
    return ok(res, row);
  } catch (e) {
    console.error('[admin.cp.custom-fee.put]', e);
    return bad(res, 500, 'Server error');
  }
});

r.get('/cp-economy/break-logs', async (req, res) => {
  try {
    let userId: number | null = null;
    if (req.query.user) {
      const u = await userCard(req.query.user);
      userId = u?.id ?? -1;
    }
    const rows = await db.cpBreakLog.findMany({
      where: userId ? { OR: [{ requesterId: userId }, { partnerId: userId }] } : {},
      orderBy: { id: 'desc' },
      take: 200,
    });
    const ids = [...new Set(rows.flatMap((x: any) => [x.requesterId, x.partnerId]))];
    const users = ids.length ? await db.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true, displayId: true } }) : [];
    const byId = new Map(users.map((u: any) => [u.id, u]));
    return ok(res, rows.map((x: any) => ({ ...x, requester: byId.get(x.requesterId), partner: byId.get(x.partnerId) })));
  } catch (e) {
    console.error('[admin.cp.break-logs]', e);
    return bad(res, 500, 'Server error');
  }
});

r.get('/cp-economy/levels', async (_req, res) => {
  try {
    const [levels, effects] = await Promise.all([
      db.cpLevel.findMany({ orderBy: { level: 'asc' } }),
      db.cpEffect.findMany({ orderBy: [{ priority: 'desc' }, { id: 'asc' }] }),
    ]);
    return ok(res, { levels, effects });
  } catch (e) {
    console.error('[admin.cp.levels]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/cp-economy/levels/:level', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const level = Math.floor(Number(req.params.level));
    if (!Number.isFinite(level) || level < 1 || level > 100) return bad(res, 400, 'رقم المستوى بين 1 و 100');
    const required = Math.floor(Number(req.body?.requiredCoins));
    if (!Number.isFinite(required) || required < 0) return bad(res, 400, 'الكوينز المطلوبة يجب أن تكون صفر أو أكثر');
    const data = {
      requiredCoins: BigInt(required),
      name: req.body?.name ? String(req.body.name).slice(0, 60) : null,
      badgeUrl: req.body?.badgeUrl ? String(req.body.badgeUrl) : null,
      frameUrl: req.body?.frameUrl ? String(req.body.frameUrl) : null,
      effectKey: req.body?.effectKey ? String(req.body.effectKey) : null,
      enabled: req.body?.enabled !== false,
    };
    // Levels must climb: each enabled level needs more than the one below it.
    const others = await db.cpLevel.findMany({ where: { enabled: true, level: { not: level } } });
    if (data.enabled) {
      for (const o of others) {
        if (o.level < level && Number(o.requiredCoins) >= required) return bad(res, 400, `المستوى ${level} يجب أن يحتاج أكثر من المستوى ${o.level} (${o.requiredCoins})`);
        if (o.level > level && Number(o.requiredCoins) <= required) return bad(res, 400, `المستوى ${level} يجب أن يحتاج أقل من المستوى ${o.level} (${o.requiredCoins})`);
      }
    }
    const before = await db.cpLevel.findUnique({ where: { level } });
    const row = await db.$transaction(async (tx: any) => {
      const out = await tx.cpLevel.upsert({ where: { level }, update: data, create: { level, ...data } });
      await recordAdminAudit(
        {
          adminId: adminId(req),
          action: AUDIT_ACTIONS.CP_LEVEL_UPDATE,
          targetType: 'cp_level',
          targetId: level,
          before: before ? { ...before, requiredCoins: String(before.requiredCoins) } : null,
          after: { ...data, requiredCoins: String(required) },
          ...auditContext(req),
          reason,
        },
        tx,
      );
      return out;
    });
    invalidateCpEffectsCache();
    return ok(res, row);
  } catch (e) {
    console.error('[admin.cp.levels.put]', e);
    return bad(res, 500, 'Server error');
  }
});

r.delete('/cp-economy/levels/:level', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const level = Math.floor(Number(req.params.level));
    const before = await db.cpLevel.findUnique({ where: { level } });
    if (!before) return bad(res, 404, 'المستوى غير موجود');
    await db.$transaction(async (tx: any) => {
      await tx.cpLevel.delete({ where: { level } });
      await recordAdminAudit(
        { adminId: adminId(req), action: AUDIT_ACTIONS.CP_LEVEL_DELETE, targetType: 'cp_level', targetId: level, before: { ...before, requiredCoins: String(before.requiredCoins) }, after: null, ...auditContext(req), reason },
        tx,
      );
    });
    invalidateCpEffectsCache();
    return ok(res, { deleted: level });
  } catch (e) {
    console.error('[admin.cp.levels.delete]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/cp-economy/effects/:key', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const key = String(req.params.key).trim();
    if (!/^[a-z0-9_-]{2,40}$/i.test(key)) return bad(res, 400, 'Effect ID: حروف وأرقام فقط');
    const b = req.body ?? {};
    const data = {
      name: b.name ? String(b.name).slice(0, 60) : null,
      requiredLevel: Math.max(0, Math.floor(Number(b.requiredLevel ?? 1))),
      enabled: Boolean(b.enabled),
      durationSec: Math.max(0, Math.min(3600, Math.floor(Number(b.durationSec ?? 0)))),
      animationSpeed: Math.max(0.25, Math.min(4, Number(b.animationSpeed ?? 1))),
      priority: Math.floor(Number(b.priority ?? 0)),
    };
    if (![data.requiredLevel, data.durationSec, data.animationSpeed, data.priority].every(Number.isFinite)) return bad(res, 400, 'قيم غير صالحة');
    const before = await db.cpEffect.findUnique({ where: { effectKey: key } });
    const row = await db.$transaction(async (tx: any) => {
      const out = await tx.cpEffect.upsert({ where: { effectKey: key }, update: data, create: { effectKey: key, ...data } });
      await recordAdminAudit(
        { adminId: adminId(req), action: AUDIT_ACTIONS.CP_EFFECT_UPDATE, targetType: 'cp_effect', targetId: key, before, after: data, ...auditContext(req), reason },
        tx,
      );
      return out;
    });
    invalidateCpEffectsCache();
    return ok(res, row);
  } catch (e) {
    console.error('[admin.cp.effects.put]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ منح المميزات ════════════════════════

r.get('/features/catalog', (_req, res) => ok(res, FEATURE_CATALOG));

r.get('/features/user/:user', async (req, res) => {
  try {
    const u = await userCard(req.params.user);
    if (!u) return bad(res, 404, 'لا يوجد مستخدم بهذا الرقم');
    return ok(res, { user: u, features: await listUserFeaturesAdmin(u.id) });
  } catch (e) {
    console.error('[admin.features.user]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/features/user/:userId/grant', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const userId = Number(req.params.userId);
    const key = String(req.body?.key ?? '').toUpperCase();
    if (!isFeatureKey(key)) return bad(res, 400, 'ميزة غير معروفة');
    const u = await db.user.findUnique({ where: { id: userId }, select: { id: true } });
    if (!u) return bad(res, 404, 'المستخدم غير موجود');
    let expiresAt: Date | null = null;
    if (req.body?.expiresAt) {
      expiresAt = new Date(String(req.body.expiresAt));
      if (!Number.isFinite(expiresAt.getTime()) || expiresAt <= new Date()) return bad(res, 400, 'تاريخ الانتهاء يجب أن يكون في المستقبل');
    }
    await grantFeature(adminId(req), userId, key, { expiresAt, note: req.body?.note ?? null, audit: { ...auditContext(req), reason } });
    return ok(res, await listUserFeaturesAdmin(userId));
  } catch (e) {
    if (e instanceof FeatureError) return bad(res, e.status, e.message, e.code);
    console.error('[admin.features.grant]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/features/user/:userId/revoke', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const userId = Number(req.params.userId);
    const key = String(req.body?.key ?? '').toUpperCase();
    if (!isFeatureKey(key)) return bad(res, 400, 'ميزة غير معروفة');
    await revokeFeature(adminId(req), userId, key, { ...auditContext(req), reason });
    return ok(res, await listUserFeaturesAdmin(userId));
  } catch (e) {
    if (e instanceof FeatureError) return bad(res, e.status, e.message, e.code);
    console.error('[admin.features.revoke]', e);
    return bad(res, 500, 'Server error');
  }
});

/** Hidden-mode entries and password bypasses: User ID, Room ID, entry, exit. */
r.get('/features/room-entries', async (req, res) => {
  try {
    const where: any = {};
    if (req.query.user) {
      const u = await userCard(req.query.user);
      where.userId = u?.id ?? -1;
    }
    if (req.query.room) where.roomId = Number(req.query.room) || -1;
    if (req.query.hiddenOnly === '1') where.hidden = true;
    const rows = await db.roomEntryLog.findMany({ where, orderBy: { id: 'desc' }, take: 300 });
    const uids = [...new Set(rows.map((x: any) => x.userId))];
    const rids = [...new Set(rows.map((x: any) => x.roomId))];
    const [users, rooms] = await Promise.all([
      uids.length ? db.user.findMany({ where: { id: { in: uids } }, select: { id: true, name: true, displayId: true } }) : [],
      rids.length ? db.room.findMany({ where: { id: { in: rids } }, select: { id: true, name: true } }) : [],
    ]);
    const uBy = new Map(users.map((u: any) => [u.id, u]));
    const rBy = new Map(rooms.map((x: any) => [x.id, x]));
    return ok(res, rows.map((x: any) => ({ ...x, user: uBy.get(x.userId), room: rBy.get(x.roomId) })));
  } catch (e) {
    console.error('[admin.features.room-entries]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ Target المضيف ════════════════════════

r.get('/host-targets/user/:user', async (req, res) => {
  try {
    const u = await userCard(req.params.user);
    if (!u) return bad(res, 404, 'لا يوجد مستخدم بهذا الرقم');
    // `active` is progress toward the period goal (gifts in the period, never
    // reduced by تبديل/بيع). `balance` is رصيد التارجت — what the host can
    // still swap or sell, and the dollars owed on it — computed by the same
    // function as the app's card, so the two pages cannot disagree.
    const [active, history, balance] = await Promise.all([
      getHostTargetView(u.id),
      listHostTargets(u.id),
      buildTargetBalance(u.id),
    ]);
    return ok(res, { user: u, active, history, balance });
  } catch (e) {
    console.error('[admin.host-targets.user]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/host-targets', async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const b = req.body ?? {};
    const row = await setHostTarget(
      {
        hostId: Number(b.hostId),
        targetCoins: Number(b.targetCoins),
        targetUsd: Number(b.targetUsd ?? 0),
        periodStart: new Date(String(b.periodStart)),
        periodEnd: new Date(String(b.periodEnd)),
        note: b.note ?? null,
        source: 'ADMIN',
        actorId: adminId(req),
      },
      { ...auditContext(req), reason },
    );
    return ok(res, { target: row, active: await getHostTargetView(Number(b.hostId)) });
  } catch (e) {
    if (e instanceof TargetError) return bad(res, e.status, e.message, e.code);
    console.error('[admin.host-targets.post]', e);
    return bad(res, 500, 'Server error');
  }
});

r.post('/host-targets/:id/cancel', async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    return ok(res, await cancelHostTarget(Number(req.params.id), adminId(req), { ...auditContext(req), reason }));
  } catch (e) {
    if (e instanceof TargetError) return bad(res, e.status, e.message, e.code);
    console.error('[admin.host-targets.cancel]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ الغرف ════════════════════════

r.get('/rooms-mgmt/:id', async (req, res) => {
  try {
    const room = await db.room.findUnique({
      where: { id: Number(req.params.id) },
      select: { id: true, name: true, ownerId: true, isActive: true, isLocked: true, roomType: true, allowHiddenEntry: true },
    });
    if (!room) return bad(res, 404, 'الغرفة غير موجودة');
    return ok(res, room);
  } catch (e) {
    console.error('[admin.rooms-mgmt.get]', e);
    return bad(res, 500, 'Server error');
  }
});

r.patch('/rooms-mgmt/:id', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    const id = Number(req.params.id);
    const before = await db.room.findUnique({ where: { id }, select: { roomType: true, allowHiddenEntry: true, isActive: true } });
    if (!before) return bad(res, 404, 'الغرفة غير موجودة');
    const data: any = {};
    if (req.body?.roomType !== undefined) {
      const t = String(req.body.roomType).toUpperCase();
      if (!['USER', 'OFFICIAL_ROOM'].includes(t)) return bad(res, 400, 'نوع الغرفة: USER أو OFFICIAL_ROOM');
      data.roomType = t;
    }
    if (req.body?.allowHiddenEntry !== undefined) data.allowHiddenEntry = Boolean(req.body.allowHiddenEntry);
    if (req.body?.isActive !== undefined) data.isActive = Boolean(req.body.isActive);
    if (!Object.keys(data).length) return bad(res, 400, 'nothing to update');
    const room = await db.$transaction(async (tx: any) => {
      const out = await tx.room.update({ where: { id }, data });
      await recordAdminAudit(
        {
          adminId: adminId(req),
          action: data.isActive === false ? AUDIT_ACTIONS.ROOM_CLOSE : AUDIT_ACTIONS.ROOM_PERMISSION_UPDATE,
          targetType: 'room',
          targetId: id,
          before,
          after: data,
          ...auditContext(req),
          reason,
        },
        tx,
      );
      return out;
    });
    if (data.isActive === false) {
      const { io } = await import('../index');
      io.to(`room:${id}`).emit('room_force_closed', { roomId: id, reason });
    }
    return ok(res, room);
  } catch (e) {
    console.error('[admin.rooms-mgmt.patch]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ ترتيب الغرف ════════════════════════
// Pinned rooms first in the given order, then the rest by people in the room
// now. See roomRanking.service.

async function describeRoomOrder() {
  const pins = await getRoomPins();
  const where = { isActive: true };
  const { ids, live, pinRanks } = await rankedRoomIds(where, FEATURED_ROOM_ID);
  const top = ids.slice(0, 30);
  const rooms = await db.room.findMany({
    where: { id: { in: Array.from(new Set([...top, ...pinRanks.keys()])) } },
    select: { id: true, name: true, ownerId: true, owner: { select: { name: true, displayId: true } } },
  });
  const byId = new Map<number, any>(rooms.map((x: any) => [x.id, x]));
  const card = (id: number) => {
    const x = byId.get(id);
    return x
      ? { id, name: x.name, ownerName: x.owner?.name ?? null, ownerDisplayId: x.owner?.displayId ?? null, liveCount: live.get(id) ?? 0 }
      : null;
  };
  const roomByRank = new Map<number, number>();
  for (const [roomId, rank] of pinRanks) roomByRank.set(rank, roomId);
  return {
    pins: pins.map((pin, i) => ({ pin, rank: i + 1, room: roomByRank.has(i) ? card(roomByRank.get(i)!) : null })),
    preview: top.map((id, i) => ({ position: i + 1, pinned: pinRanks.has(id), featured: id === FEATURED_ROOM_ID, ...card(id) })),
  };
}

r.get('/room-order', async (_req, res) => {
  try {
    return ok(res, await describeRoomOrder());
  } catch (e) {
    console.error('[admin.room-order.get]', e);
    return bad(res, 500, 'Server error');
  }
});

r.put('/room-order', requireSuperAdmin, async (req, res) => {
  try {
    const reason = needReason(req, res);
    if (!reason) return;
    if (!Array.isArray(req.body?.pins)) return bad(res, 400, 'pins: قائمة الـ ID بالترتيب');
    const pins = parsePins(req.body.pins);
    if (pins.length > MAX_ROOM_PINS) return bad(res, 400, `الحد الأقصى ${MAX_ROOM_PINS} غرفة`);
    // Every pin must point at an active room — a typo must not be saved silently.
    const rows = await db.room.findMany({
      where: { isActive: true },
      select: { id: true, ownerId: true, createdAt: true, owner: { select: { displayId: true } } },
    });
    const ranks = resolvePinRanks(pins, rows);
    const found = new Set(ranks.values());
    const missing = pins.filter((_p, i) => !found.has(i));
    if (missing.length) return bad(res, 400, `لا توجد غرفة نشطة لهذا الـ ID: ${missing.join(', ')}`, 'ROOM_NOT_FOUND');

    const before = await getRoomPins();
    await db.$transaction(async (tx: any) => {
      const value = JSON.stringify(pins);
      await tx.appSetting.upsert({ where: { key: ROOM_PIN_KEY }, update: { value }, create: { key: ROOM_PIN_KEY, value } });
      await recordAdminAudit(
        { adminId: adminId(req), action: AUDIT_ACTIONS.ROOM_ORDER_UPDATE, targetType: 'room_order', before, after: pins, ...auditContext(req), reason },
        tx,
      );
    });
    invalidateRoomPins();
    return ok(res, await describeRoomOrder());
  } catch (e) {
    console.error('[admin.room-order.put]', e);
    return bad(res, 500, 'Server error');
  }
});

// ════════════════════════ سجل المراجعة ════════════════════════

r.get('/audit-log', async (req, res) => {
  try {
    let targetUserId: number | undefined;
    if (req.query.user) {
      const u = await userCard(req.query.user);
      targetUserId = u?.id ?? -1;
    }
    const from = req.query.from ? new Date(String(req.query.from)) : undefined;
    const to = req.query.to ? new Date(String(req.query.to)) : undefined;
    return ok(
      res,
      await auditLog({
        action: req.query.action ? String(req.query.action) : undefined,
        adminId: req.query.admin ? Number(req.query.admin) || undefined : undefined,
        targetUserId,
        from: from && Number.isFinite(from.getTime()) ? from : undefined,
        to: to && Number.isFinite(to.getTime()) ? to : undefined,
        page: Number(req.query.page) || 1,
      }),
    );
  } catch (e) {
    console.error('[admin.audit-log]', e);
    return bad(res, 500, 'Server error');
  }
});
