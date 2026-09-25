import express from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard, requireSuperAdmin } from '../middlewares/adminDashboard.middleware';
import { clientLogFiles, tailJsonl } from './appDownload.routes';
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

const router = express.Router();

router.use(authenticate);
router.use(requireAdminDashboard);

// ── 2026-09-22: صلاحيات فتح CP + إدارة نظام CP والخلفيات ──────────────────
// Sub-routers, so they inherit the two gates above (JWT + isAdmin on the row)
// and every action inside writes admin_audit_logs.
router.use('/cp', adminCpRouter);
router.use('/backgrounds', adminBackgroundsRouter);

router.get('/overview', adminDashboardOverview);

// Admin roster (#23). Reading the roster + own role needs only dashboard access;
// mutating it requires super-admin.
router.get('/me', adminDashboardMe);
router.get('/admins', adminListAdmins);
router.post('/admins/:userId/grant', requireSuperAdmin, adminGrantAdmin);
router.post('/admins/:userId/revoke', requireSuperAdmin, adminRevokeAdmin);
router.patch('/admins/:userId/super', requireSuperAdmin, adminSetSuperAdmin);
router.get('/users', adminDashboardListUsers);
router.patch('/users/:id/ban', adminDashboardBanUser);
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
router.get('/transactions', adminDashboardTransactions);
router.post('/broadcast', adminDashboardBroadcast);
router.get('/topup-requests', adminDashboardTopupRequests);
router.patch('/topup-requests/:id/review', adminDashboardReviewTopupRequest);
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
router.patch('/agencies/:id/topup', adminTopupAgency);
// B11 — automatic charge rewards ladder
router.get('/agency-charge-rewards', adminListAgencyChargeRewards);
router.post('/agency-charge-rewards', adminSaveAgencyChargeReward);
router.delete('/agency-charge-rewards/:id', adminDeleteAgencyChargeReward);
router.patch('/agencies/:id/target', adminSetAgencyTarget);
router.get('/agencies/:id/members', adminListAgencyMembers);
router.delete('/agency-members/:memberId', adminRemoveAgencyMember);
// B8 - add/deduct one member's target (negative amountCoins deducts).
router.post('/agency-members/:memberId/target-adjust', adminAdjustMemberTarget);
// B13 — same operation addressed by user (displayId or internal id), so a
// target can be adjusted from the user search instead of only from an
// agency's member list. `?by=id` forces the internal-id reading.
router.post('/users/:id/target-adjust', adminAdjustUserTarget);
// B9 - top supporters board + per-account counter reset.
router.get('/top-supporters', adminListTopSupporters);
router.post('/users/:id/reset-supporter-counter', adminResetSupporterCounter);
router.get('/gifts', authenticate, adminListGifts);
router.post('/gifts', authenticate, adminCreateGift);
router.patch('/gifts/:id', authenticate, adminUpdateGift);
router.delete('/gifts/:id', authenticate, adminDeleteGift);

router.get('/vip-levels', adminListVipLevels);
router.post('/vip-levels', adminUpsertVipLevel);

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
router.patch('/settings', require('../controllers/settings.controller').updateSettings);


// ── A15: قائمة المكافآت ──────────────────────────────────────────────────
router.get('/rewards/room-cup', adminListRoomCupRewards);
router.post('/rewards/room-cup', adminSaveRoomCupReward);
router.delete('/rewards/room-cup/:id', adminDeleteRoomCupReward);
router.get('/rewards/supporters', adminListSupporterRewards);
router.post('/rewards/supporters', adminSaveSupporterReward);
router.delete('/rewards/supporters/:id', adminDeleteSupporterReward);

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
router.post('/gates', adminSetGates);

// ── G3(d): لوحة تحكم الألعاب ─────────────────────────────────────────────
router.get('/games', adminListGameConfig);
router.post('/games/:game', adminSetGameConfig);
router.get('/games-halal', adminGetHalalGames);
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

export default router;
