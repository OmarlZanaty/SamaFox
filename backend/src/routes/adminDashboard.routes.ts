import express from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard } from '../middlewares/adminDashboard.middleware';
import {
  adminDashboardAnalytics,
  adminDashboardBanUser,
  adminDashboardBroadcast,
  adminChangeUserDisplayId,
  adminDashboardCreateQuest,
  adminDashboardDeleteQuest,
  adminDashboardForceCloseRoom,
  adminDashboardGetQuests,
  adminDashboardLeaderboard,
  adminDashboardListChargingAgencies,
  adminDashboardListRooms,
  adminDashboardListUsers,
  adminDashboardOverview,
  adminDashboardReports,
  adminDashboardReviewTopupRequest,
  adminDashboardTopupRequests,
  adminDashboardTransactions,
  adminDashboardUpdateAgencyStatus,
  adminDashboardUpdateReport,
  adminListAgencyRequests,
  adminReviewAgencyRequest,
  adminTopupAgency,
  adminSetAgencyTarget,
  adminCreateGift,
  adminDeleteGift,
  adminListGifts,
  adminUpdateGift,
} from '../controllers/adminDashboard.controller';

const router = express.Router();

router.use(authenticate);
router.use(requireAdminDashboard);

router.get('/overview', adminDashboardOverview);
router.get('/users', adminDashboardListUsers);
router.patch('/users/:id/ban', adminDashboardBanUser);
router.patch('/users/:id/display-id', authenticate, adminChangeUserDisplayId);
router.get('/transactions', adminDashboardTransactions);
router.post('/broadcast', adminDashboardBroadcast);
router.get('/topup-requests', adminDashboardTopupRequests);
router.patch('/topup-requests/:id/review', adminDashboardReviewTopupRequest);
router.get('/analytics', adminDashboardAnalytics);
router.get('/reports', adminDashboardReports);
router.patch('/reports/:id', adminDashboardUpdateReport);
router.get('/rooms', adminDashboardListRooms);
router.post('/rooms/:id/force-close', adminDashboardForceCloseRoom);
router.get('/quests', adminDashboardGetQuests);
router.post('/quests', adminDashboardCreateQuest);
router.delete('/quests/:id', adminDashboardDeleteQuest);
router.get('/leaderboard', adminDashboardLeaderboard);

router.get('/charging-agencies', adminDashboardListChargingAgencies);
router.patch('/charging-agencies/:id/status', adminDashboardUpdateAgencyStatus);
router.get('/agency-requests', adminListAgencyRequests);
router.patch('/agency-requests/:id/review', adminReviewAgencyRequest);
router.patch('/agencies/:id/topup', adminTopupAgency);
router.patch('/agencies/:id/target', adminSetAgencyTarget);
router.get('/gifts', authenticate, adminListGifts);
router.post('/gifts', authenticate, adminCreateGift);
router.patch('/gifts/:id', authenticate, adminUpdateGift);
router.delete('/gifts/:id', authenticate, adminDeleteGift);

export default router;
