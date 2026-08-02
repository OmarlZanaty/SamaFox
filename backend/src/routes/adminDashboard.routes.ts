import express from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard, requireSuperAdmin } from '../middlewares/adminDashboard.middleware';
import {
  adminDashboardAnalytics,
  adminDashboardBanUser,
  adminDashboardBroadcast,
  adminChangeUserDisplayId,
  adminUpdateUserProfile,
  adminUpdateUserProgression,
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
  adminDashboardMe,
  adminListAdmins,
  adminGrantAdmin,
  adminRevokeAdmin,
  adminSetSuperAdmin,
} from '../controllers/adminDashboard.controller';

const router = express.Router();

router.use(authenticate);
router.use(requireAdminDashboard);

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
router.patch('/agencies/:id/target', adminSetAgencyTarget);
router.get('/agencies/:id/members', adminListAgencyMembers);
router.delete('/agency-members/:memberId', adminRemoveAgencyMember);
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

export default router;
