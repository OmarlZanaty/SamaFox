import { idempotent } from '../middlewares/idempotency.middleware';
import express from 'express';
import { banUserName, banUserImage, listNameBans, listImageBans, deleteNameBan, deleteImageBan, listBanBypass, addBanBypass, deleteBanBypass } from '../controllers/adminNameImageBan.controller';
import { createRoomCup, listRoomCups, deleteRoomCup, listRoomCupClaims } from '../controllers/adminRoomCup.controller';
import prisma from '../utils/prisma';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard, requireSuperAdmin } from '../middlewares/adminDashboard.middleware';
import { clientLogFiles, tailJsonl } from './appDownload.routes';
import { readClientHealth, type HealthRow } from '../services/clientHealth';
import {
  adminDashboardAnalytics,
  adminDashboardBanUser,
  adminDashboardBroadcast,
  adminChangeUserDisplayId,
  adminUpdateUserProfile,
  adminUpdateUserProgression,
  adminDashboardSetTargetLock,
  adminDashboardListTargetLocks,
  adminDashboardGetTargetSellPolicy,
  adminDashboardSetTargetSellPolicy,
  adminDashboardGetCoinFreeze,
  adminDashboardSetCoinFreezeGlobal,
  adminDashboardSetUserCoinFreeze,
  adminDashboardCreateQuest,
  adminDashboardDeleteQuest,
  adminDashboardForceCloseRoom,
  adminDashboardGetQuests,
  adminDashboardLeaderboard,
  adminDashboardListChargingAgencies,
  adminDashboardListRooms,
  adminDashboardUpdateRoom,
  adminDashboardRoomDetails,
  adminDashboardListUsers,
  adminDashboardOverview,
  adminDashboardReports,
  adminDashboardReviewTopupRequest,
  adminDashboardTopupRequests,
  adminDashboardTransactions,
  adminDashboardUpdateAgencyStatus,
  adminDashboardUpdateAgency,
  adminDashboardAgencyCharges,
  adminDashboardUpdateReport,
  adminListAgencyRequests,
  adminReviewAgencyRequest,
  adminAssignAgency,
  adminListAssignedAgencies,
  adminTopupAgency,
  adminWithdrawAgency,
  adminFreezeAgencyWallet,
  adminFreezeAllAgencyWallets,
  adminListAgencyChargeRewards,
  adminSaveAgencyChargeReward,
  adminDeleteAgencyChargeReward,
  adminSetAgencyTarget,
  adminCreateGift,
  adminDeleteGift,
  adminListGifts,
  adminUpdateGift,
  adminListVipLevels,
  adminUpsertVipLevel,
  adminListLevels,
  adminUpsertLevel,
  adminDeleteLevel,
  adminBackfillLevelRewards,
  adminListTargetTiers,
  adminCreateTargetTier,
  adminUpdateTargetTier,
  adminDeleteTargetTier,
  adminListAgencyMembers,
  adminRemoveAgencyMember,
  adminAdjustMemberTarget,
  adminAdjustUserTarget,
  adminListTargetMovements,
  adminListRoomCupRewards,
  adminSaveRoomCupReward,
  adminDeleteRoomCupReward,
  adminListSupporterRewards,
  adminSaveSupporterReward,
  adminDeleteSupporterReward,
  adminGetRoomSupportWindow,
  adminSetRoomSupportWindow,
  adminSendMessage,
  adminListDeviceBans,
  adminCreateDeviceBan,
  adminDeleteDeviceBan,
  adminUserChargeHistory,
  adminGetGates,
  adminLuckySummary,
  adminSetGates,
  adminListGameConfig,
  adminSetGameConfig,
  adminGetHalalGames,
  adminSetHalalGames,
  adminListTopSupporters,
  adminResetSupporterCounter,
  adminDashboardMe,
  adminListAdmins,
  adminGrantAdmin,
  adminRevokeAdmin,
  adminSetSuperAdmin,
} from '../controllers/adminDashboard.controller';
import { adminBackgroundsRouter, adminCpRouter } from './adminCp.routes';
import { adminEconomyRouter } from './adminEconomy.routes';
import { auditContext, recordAdminAudit } from '../services/adminAudit.service';
import {
  OWNER_PERMISSIONS,
  OWNER_PERMISSION_DENIED,
  capabilitiesFor,
  grantPermission,
  hasOwnerPermission,
  isOwnerPermission,
  listGrants,
  requireOwner,
  requireOwnerPermission,
  revokePermission,
} from '../services/ownerPermissions.service';

const router = express.Router();

// PATCH /settings is a generic key/value store. Keys that move money (prices,
// rates, pools, recharge) need an owner permission; display toggles do not.
const FINANCIAL_SETTING = /price|coin|recharge|reward|pool|fee|commission|rate|payout|exchange|dollar|bonus|package|wallet/i;
async function requireFinancialSettingsPermission(req: any, res: any, next: any) {
  const keys = Object.keys(req.body ?? {});
  if (!keys.some((k) => FINANCIAL_SETTING.test(k))) return next();
  const perm = keys.some((k) => /recharge|package|dollar|exchange/i.test(k)) ? 'finance.recharge' : 'economy.settings';
  if (await hasOwnerPermission(Number(req.userId), perm)) return next();
  return res.status(403).json({ success: false, code: 'OWNER_PERMISSION_REQUIRED', permission: perm, message: OWNER_PERMISSION_DENIED });
}

router.use(authenticate);
router.use(requireAdminDashboard);

router.get('/room-sessions', async (req, res) => {
  try {
    const where: any = {};
    for (const key of ['userId', 'roomId'] as const) {
      if (!req.query[key]) continue;
      const value = Number(req.query[key]);
      if (!Number.isSafeInteger(value) || value <= 0) return res.status(400).json({ success: false, message: 'Invalid filter' });
      where[key] = value;
    }
    const from = req.query.from ? new Date(String(req.query.from)) : new Date(Date.now() - 7 * 86400000);
    const to = req.query.to ? new Date(String(req.query.to)) : new Date();
    if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to) {
      return res.status(400).json({ success: false, message: 'Invalid dates' });
    }
    where.joinedAt = { gte: from, lte: to };
    const page = Math.min(10000, Math.max(1, Math.floor(Number(req.query.page) || 1)));
    const rows = await prisma.roomSession.findMany({
      where, orderBy: [{ joinedAt: 'desc' }, { id: 'desc' }], skip: (page - 1) * 100, take: 101,
    });
    return res.json({ success: true, data: rows.slice(0, 100), page, hasMore: rows.length > 100 });
  } catch (e) {
    console.error('[admin.room-sessions]', e);
    return res.status(500).json({ success: false, message: 'Unable to load sessions' });
  }
});

// Item 20 — every administrative change is in admin_audit_logs. The pages that
// write their own detailed rows (before/after, reason) are skipped here; every
// OTHER mutating dashboard call — agency approvals, target adjustments, bans,
// store edits… — gets a generic row with the path, the body and the result.
const SELF_AUDITED = /^\/(cp|backgrounds|games-economy|lucky-mgmt|cp-economy|features|host-targets|rooms-mgmt)(\/|$)/;
router.use((req: any, res: any, next: any) => {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS' || SELF_AUDITED.test(req.path)) return next();
  res.on('finish', () => {
    let body: unknown = null;
    try {
      // Secrets never reach the log.
      const raw = JSON.stringify(req.body ?? null, (k, v) => (/pass|token|secret|pin|accesscode/i.test(k) ? '***' : v));
      body = raw && raw.length > 4000 ? { truncated: raw.slice(0, 4000) } : JSON.parse(raw ?? 'null');
    } catch {
      body = null;
    }
    const idMatch = /\/(?:users|agencies|agency-members|rooms)\/(\d+)/.exec(req.path);
    recordAdminAudit({
      adminId: Number(req.userId),
      action: `DASHBOARD_${req.method}`,
      targetType: req.path.split('/')[1] || null,
      targetId: req.path,
      targetUserId: /\/users\/(\d+)/.test(req.path) && idMatch ? Number(idMatch[1]) : null,
      before: null,
      after: { body, status: res.statusCode },
      ...auditContext(req),
    }).catch(() => undefined);
  });
  return next();
});

// ── 2026-09-22: صلاحيات فتح CP + إدارة نظام CP والخلفيات ──────────────────
// Sub-routers, so they inherit the two gates above (JWT + isAdmin on the row)
// and every action inside writes admin_audit_logs.
router.use('/cp', adminCpRouter);
router.use('/backgrounds', adminBackgroundsRouter);
// ── 2026-09-26: اقتصاد الألعاب، المحظوظ، CP، منح المميزات، التارجت، سجل المراجعة ──
router.use(adminEconomyRouter);

router.get('/overview', adminDashboardOverview);

// Admin roster (#23). Reading the roster + own role needs only dashboard access;
// mutating it requires super-admin.
router.get('/me', adminDashboardMe);
// SPEC52 #42 — what this admin may do with money/prices/products (the server
// still checks every call), and the owner's grant management.
router.get('/me/capabilities', async (req: any, res) => {
  try {
    return res.json({ success: true, data: await capabilitiesFor(Number(req.userId)) });
  } catch (e) {
    return res.status(500).json({ success: false, message: (e as Error).message });
  }
});
// SPEC52 #41 — store lists + products (owner permission store.products).
const storeWrap = (fn: (req: any) => Promise<unknown>) => async (req: any, res: any) => {
  try {
    return res.json({ success: true, data: await fn(req) });
  } catch (e: any) {
    if (e?.status) return res.status(e.status).json({ success: false, message: e.message });
    console.error('[admin.store-lists]', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};
const SL = () => import('../services/storeLists.service');
router.get('/store-lists', storeWrap(async () => (await SL()).adminList()));
router.post('/store-lists', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).saveCategory(req)));
router.patch('/store-lists/:id', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).saveCategory(req)));
router.delete('/store-lists/:id', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).deleteCategory(req)));
router.post('/store-lists/products', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).saveProduct(req)));
router.patch('/store-lists/products/:productId', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).saveProduct(req)));
router.delete('/store-lists/products/:productId', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).deleteProduct(req)));
router.post('/store-lists/bulk-ids', requireOwnerPermission('store.products'), storeWrap(async (req) => (await SL()).bulkAddIds(req)));

router.get('/special-ids', requireOwnerPermission('store.products'), storeWrap(async (req) =>
  (await SL()).listSpecialIds(req.query.userId === undefined ? undefined : Number(req.query.userId))));
router.post('/special-ids/grant', requireOwnerPermission('store.products'), storeWrap(async (req) =>
  (await SL()).grantSpecialId(Number(req.userId), Number(req.body?.userId), Number(req.body?.displayId),
    req.body?.durationDays == null ? null : Number(req.body.durationDays))));
router.post('/special-ids/revoke', requireOwnerPermission('store.products'), storeWrap(async (req) =>
  (await SL()).revokeSpecialId(Number(req.userId), Number(req.body?.userId))));

router.get('/permissions/catalog', (_req, res) => {
  res.json({
    success: true,
    data: Object.entries(OWNER_PERMISSIONS).map(([key, label]) => ({ key, label, delegable: key !== 'admin.permissions' })),
  });
});
router.get('/permissions/grants', requireOwner, async (_req, res) => {
  try {
    return res.json({ success: true, data: await listGrants() });
  } catch (e) {
    return res.status(500).json({ success: false, message: (e as Error).message });
  }
});
router.post('/permissions/grants', requireOwner, async (req: any, res) => {
  try {
    const userId = Number(req.body?.userId);
    const permission = req.body?.permission;
    if (!userId || !isOwnerPermission(permission)) return res.status(400).json({ success: false, message: 'userId و permission مطلوبة' });
    if (permission === 'admin.permissions') return res.status(400).json({ success: false, message: 'هذه الصلاحية للمالك فقط ولا تُمنح' });
    return res.json({ success: true, data: await grantPermission(req, userId, permission) });
  } catch (e: any) {
    return res.status(e?.status ?? 500).json({ success: false, message: e?.message ?? 'failed' });
  }
});
router.delete('/permissions/grants/:id', requireOwner, async (req: any, res) => {
  try {
    return res.json({ success: true, data: await revokePermission(req, Number(req.params.id)) });
  } catch (e: any) {
    return res.status(e?.status ?? 500).json({ success: false, message: e?.message ?? 'failed' });
  }
});
router.get('/admins', adminListAdmins);
router.post('/admins/:userId/grant', requireSuperAdmin, adminGrantAdmin);
router.post('/admins/:userId/revoke', requireSuperAdmin, adminRevokeAdmin);
router.patch('/admins/:userId/super', requireSuperAdmin, adminSetSuperAdmin);
router.get('/users', adminDashboardListUsers);
router.patch('/users/:id/ban', adminDashboardBanUser);
// Same authenticate + requireAdminDashboard gates as account moderation above.
router.post('/name-bans/user/:userId', banUserName);
router.post('/image-bans/user/:userId', banUserImage);
router.get('/name-bans', listNameBans);
router.delete('/name-bans/:id', deleteNameBan);
router.get('/image-bans', listImageBans);
router.delete('/image-bans/:id', deleteImageBan);
router.get('/ban-bypass', listBanBypass);
router.post('/ban-bypass', addBanBypass);
router.delete('/ban-bypass/:userId', deleteBanBypass);
router.patch('/users/:id/display-id', authenticate, adminChangeUserDisplayId);
router.patch('/users/:id/profile', adminUpdateUserProfile);
router.patch('/users/:id/progression', adminUpdateUserProgression);
// Target payout lock (owner request): stop/allow بيع واستبدال التارجيت.
// The global freeze is super-admin only — it stops payouts for the whole
// platform, so a plain dashboard admin must not be able to lift it.
router.patch('/users/:id/target-lock', adminDashboardSetTargetLock);
router.get('/target-locks', adminDashboardListTargetLocks);
router.get('/target-sell-policy', adminDashboardGetTargetSellPolicy);
router.patch('/target-sell-policy', requireSuperAdmin, adminDashboardSetTargetSellPolicy);
// تجميد الكوينزات (owner request, 2026-10-01). Same split as the target freeze:
// the platform-wide switch is super-admin only, freezing one account is not.
router.get('/coin-freeze', adminDashboardGetCoinFreeze);
router.patch('/coin-freeze', requireOwnerPermission('finance.coins'), adminDashboardSetCoinFreezeGlobal);
router.patch('/users/:id/coin-freeze', requireOwnerPermission('finance.coins'), adminDashboardSetUserCoinFreeze);
router.get('/transactions', adminDashboardTransactions);
router.post('/broadcast', adminDashboardBroadcast);
router.get('/topup-requests', adminDashboardTopupRequests);
router.patch('/topup-requests/:id/review', requireOwnerPermission('finance.recharge'), adminDashboardReviewTopupRequest);
router.get('/analytics', adminDashboardAnalytics);
router.get('/reports', adminDashboardReports);
router.patch('/reports/:id', adminDashboardUpdateReport);
router.get('/rooms', adminDashboardListRooms);
router.patch('/rooms/:id', adminDashboardUpdateRoom);
router.get('/rooms/:id/details', adminDashboardRoomDetails);
router.post('/rooms/:id/force-close', adminDashboardForceCloseRoom);
router.get('/quests', adminDashboardGetQuests);
router.post('/quests', adminDashboardCreateQuest);
router.delete('/quests/:id', adminDashboardDeleteQuest);
router.get('/leaderboard', adminDashboardLeaderboard);


router.get('/charging-agencies', adminDashboardListChargingAgencies);
router.patch('/charging-agencies/:id/status', adminDashboardUpdateAgencyStatus);
router.patch('/agencies/:id', adminDashboardUpdateAgency);
router.get('/agencies/:id/charges', adminDashboardAgencyCharges);
router.get('/agency-requests', adminListAgencyRequests);
router.patch('/agency-requests/:id/review', adminReviewAgencyRequest);
router.post('/agencies/assign', adminAssignAgency);
router.get('/agencies/assigned-by-me', adminListAssignedAgencies);
router.patch('/agencies/:id/topup', requireOwnerPermission('finance.charging_agency'), idempotent('admin_agency_topup'), adminTopupAgency);
router.patch('/agencies/:id/withdraw', requireOwnerPermission('finance.charging_agency'), idempotent('admin_agency_withdraw'), adminWithdrawAgency);
router.patch('/charging-agencies/:id/freeze', requireOwnerPermission('finance.charging_agency'), adminFreezeAgencyWallet);
router.put('/charging-agencies/freeze', requireOwnerPermission('finance.charging_agency'), adminFreezeAllAgencyWallets);
// B11 — automatic charge rewards ladder
router.get('/agency-charge-rewards', adminListAgencyChargeRewards);
router.post('/agency-charge-rewards', requireOwnerPermission('finance.charging_agency'), adminSaveAgencyChargeReward);
router.delete('/agency-charge-rewards/:id', requireOwnerPermission('finance.charging_agency'), adminDeleteAgencyChargeReward);
router.patch('/agencies/:id/target', adminSetAgencyTarget);
router.get('/agencies/:id/members', adminListAgencyMembers);
router.delete('/agency-members/:memberId', adminRemoveAgencyMember);
// B8 - add/deduct one member's target (negative amountCoins deducts).
router.post('/agency-members/:memberId/target-adjust', adminAdjustMemberTarget);
// B13 — same operation addressed by user (displayId or internal id), so a
// target can be adjusted from the user search instead of only from an
// agency's member list. `?by=id` forces the internal-id reading.
router.post('/users/:id/target-adjust', adminAdjustUserTarget);
router.get('/target-movements', adminListTargetMovements);
// B9 - top supporters board + per-account counter reset.
router.get('/top-supporters', adminListTopSupporters);
router.post('/users/:id/reset-supporter-counter', adminResetSupporterCounter);
router.get('/gifts', authenticate, adminListGifts);
router.post('/gifts', authenticate, requireOwnerPermission('gifts.prices'), adminCreateGift);
router.patch('/gifts/:id', authenticate, requireOwnerPermission('gifts.prices'), adminUpdateGift);
router.delete('/gifts/:id', authenticate, requireOwnerPermission('gifts.prices'), adminDeleteGift);

router.get('/vip-levels', adminListVipLevels);
router.post('/vip-levels', requireOwnerPermission('vip.config'), adminUpsertVipLevel);

router.get('/levels', adminListLevels);
router.post('/levels', adminUpsertLevel);
router.post('/levels/backfill', adminBackfillLevelRewards);
router.delete('/levels/:level', adminDeleteLevel);

router.get('/target-tiers', adminListTargetTiers);
router.post('/target-tiers', adminCreateTargetTier);
router.patch('/target-tiers/:id', adminUpdateTargetTier);
router.delete('/target-tiers/:id', adminDeleteTargetTier);

// CP / target settings — on the dashboard router so the dashboard token (authenticate +
// requireAdminDashboard) is accepted. It was previously only on /admin/settings, which
// uses a different auth the dashboard doesn't hold → the save returned 401.
router.patch('/settings', requireFinancialSettingsPermission, require('../controllers/settings.controller').updateSettings);


// ── A15: قائمة المكافآت ──────────────────────────────────────────────────
router.get('/rewards/room-cup', adminListRoomCupRewards);
router.get('/rewards/room-cups', requireOwnerPermission('economy.settings'), listRoomCups);
router.get('/rewards/room-cup-claims', requireOwnerPermission('economy.settings'), listRoomCupClaims);
router.post('/rewards/room-cups', requireOwnerPermission('economy.settings'), createRoomCup);
router.delete('/rewards/room-cups/:id', requireOwnerPermission('economy.settings'), deleteRoomCup);
router.post('/rewards/room-cup', requireOwnerPermission('economy.settings'), adminSaveRoomCupReward);
router.delete('/rewards/room-cup/:id', requireOwnerPermission('economy.settings'), adminDeleteRoomCupReward);
router.get('/rewards/supporters', adminListSupporterRewards);
router.post('/rewards/supporters', requireOwnerPermission('economy.settings'), adminSaveSupporterReward);
router.delete('/rewards/supporters/:id', requireOwnerPermission('economy.settings'), adminDeleteSupporterReward);

// ── A14: مدة تصفير إجمالي دعم الروم ──────────────────────────────────────
router.get('/rewards/room-support-window', adminGetRoomSupportWindow);
router.post('/rewards/room-support-window', adminSetRoomSupportWindow);

// ── F3: رسائل الإدارة ────────────────────────────────────────────────────
router.post('/messages', adminSendMessage);

// ── F4: حظر الجهاز / الشبكة ──────────────────────────────────────────────
router.get('/device-bans', adminListDeviceBans);
router.post('/device-bans', adminCreateDeviceBan);
router.delete('/device-bans/:id', adminDeleteDeviceBan);

// ── B14: سجل شحنات مستخدم ────────────────────────────────────────────────
router.get('/users/:id/charges', adminUserChargeHistory);

// ── C16 / C18: بوابات الليفل والـVIP ─────────────────────────────────────
router.get('/gates', adminGetGates);

// ── هدايا الحظ: الصندوق، جدول المضاعفات، آخر الرميات ─────────────────────────
router.get('/lucky', adminLuckySummary);
// 2026-09-26: superseded by /lucky-mgmt/* (validated against the 30/70 split
// and the RTP target, super-admin only, with a reason in the audit log).
const retiredLucky = (_req: any, res: any) =>
  res.status(410).json({ success: false, message: 'استخدم صفحة الألعاب ← إدارة المحظوظ' });
router.post('/lucky/tiers', retiredLucky);
router.post('/lucky/topup', retiredLucky);
router.post('/gates', requireOwnerPermission('vip.config'), adminSetGates);

// ── G3(d): لوحة تحكم الألعاب ─────────────────────────────────────────────
router.get('/games', adminListGameConfig);
router.post('/games/:game', requireOwnerPermission('economy.settings'), adminSetGameConfig);
router.get('/games-halal', adminGetHalalGames);
// Per game, per Cairo day: coins staked vs coins paid out, from game_ledger.
// GET /admin-dashboard/games-rtp?days=14
router.get('/games-rtp', async (req, res) => {
  try {
    const { gamesRtp } = await import('../services/gamesRtp.service');
    res.json({ success: true, data: await gamesRtp(Number(req.query.days) || 14) });
  } catch (e) {
    console.error('[games-rtp]', e);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});
router.post('/games-halal', adminSetHalalGames);

// ── Client logs (what the app is doing on users' phones) ─────────────────────
//
// GET /admin-dashboard/client-logs?minutes=60&userId=12&level=error&q=mic&limit=500
//
// Reads the tail of logs/client-events.log (live events) and
// logs/client-reports.log (crashes / OS kills), newest first. Filters are
// applied server-side so the page stays light on a phone.
router.get('/client-logs', (req, res) => {
  try {
    const minutes = Math.min(Math.max(Number(req.query.minutes) || 60, 1), 60 * 24 * 7);
    const limit = Math.min(Math.max(Number(req.query.limit) || 500, 1), 5000);
    const userId = Number(req.query.userId) || null;
    const room = Number(req.query.room) || null;
    const level = typeof req.query.level === 'string' ? req.query.level : '';
    const q = typeof req.query.q === 'string' ? req.query.q.trim().toLowerCase() : '';
    const since = Date.now() - minutes * 60 * 1000;

    const events = tailJsonl(clientLogFiles.events())
      .filter((e) => Date.parse(String(e.rx ?? e.t)) >= since)
      .filter((e) => !userId || e.userId === userId)
      .filter((e) => !room || e.room === room)
      .filter((e) => !level || e.level === level)
      .filter((e) => !q || JSON.stringify(e).toLowerCase().includes(q));

    const reports = tailJsonl(clientLogFiles.reports(), 2 * 1024 * 1024)
      .filter((r) => Date.parse(String(r.receivedAt)) >= since)
      .filter((r) => !q || JSON.stringify(r).toLowerCase().includes(q))
      .map((r) => ({
        t: r.at ?? r.receivedAt,
        rx: r.receivedAt,
        level: 'error',
        kind: 'crash',
        msg: `${r.kind}: ${r.message ?? ''}`,
        userId: null,
        room: null,
        app: r.appVersion ?? null,
        device: r.platform ?? null,
        session: null,
        data: { peakRssMb: r.peakRssMb, stack: r.stack, breadcrumbs: r.breadcrumbs },
      }));

    const all = [...events, ...reports]
      .sort((a, b) => Date.parse(String(b.rx)) - Date.parse(String(a.rx)))
      .slice(0, limit);

    // A quick shape of the window, for the header of the page.
    const summary = {
      total: all.length,
      errors: all.filter((e) => e.level === 'error').length,
      warns: all.filter((e) => e.level === 'warn').length,
      users: new Set(all.map((e) => e.userId).filter(Boolean)).size,
      apps: Array.from(new Set(all.map((e) => e.app).filter(Boolean))),
    };
    return res.json({ success: true, minutes, summary, items: all });
  } catch (e) {
    console.error('[admin.client-logs]', e);
    return res.status(500).json({ success: false, message: 'Failed to read logs' });
  }
});


// ── Client health (per day × app version) ────────────────────────────────────
//
// GET /admin-dashboard/client-health?days=7
//
// OS kills, forced logouts, lost connections and memory from the client logs,
// so each release can be judged by numbers. Reading ~100 MB of logs takes a
// few seconds, so a result is kept for ten minutes.
const healthCache = new Map<number, { at: number; rows: HealthRow[] }>();
router.get('/client-health', async (req, res) => {
  try {
    const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 30);
    const hit = healthCache.get(days);
    if (hit && Date.now() - hit.at < 10 * 60 * 1000) {
      return res.json({ success: true, days, generatedAt: new Date(hit.at).toISOString(), rows: hit.rows });
    }
    const since = Date.now() - days * 24 * 60 * 60 * 1000;
    const rows = await readClientHealth({ events: clientLogFiles.events(), reports: clientLogFiles.reports() }, since);
    const at = Date.now();
    healthCache.set(days, { at, rows });
    return res.json({ success: true, days, generatedAt: new Date(at).toISOString(), rows });
  } catch (e) {
    console.error('[admin.client-health]', e);
    return res.status(500).json({ success: false, message: 'Failed to read logs' });
  }
});

export default router;
