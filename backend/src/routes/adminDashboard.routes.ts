import express from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard } from '../middlewares/admin.middleware';
import {
  adminDashboardOverview,
  adminDashboardListUsers,
  adminDashboardBanUser,
  adminDashboardListRooms,
  adminDashboardForceCloseRoom,
  adminDashboardListChargingAgencies,
  adminDashboardUpdateAgencyStatus,
  adminDashboardListTransactions,
  adminDashboardBroadcast,
  adminDashboardListTopups,
  adminDashboardReviewTopup,
  adminDashboardAnalytics,
  adminDashboardListReports,
  adminDashboardResolveReport,
  adminDashboardListQuests,
  adminDashboardCreateQuest,
  adminDashboardUpdateQuest,
  adminDashboardDeleteQuest,
  adminDashboardLeaderboard,
} from '../controllers/adminDashboard.controller';

const router = express.Router();

router.use(authenticate, requireAdminDashboard);

router.get('/overview', adminDashboardOverview);
router.get('/users', adminDashboardListUsers);
router.patch('/users/:id/ban', adminDashboardBanUser);
router.get('/rooms', adminDashboardListRooms);
router.post('/rooms/:id/force-close', adminDashboardForceCloseRoom);
router.get('/charging-agencies', adminDashboardListChargingAgencies);
router.patch('/charging-agencies/:id/status', adminDashboardUpdateAgencyStatus);
router.get('/transactions', adminDashboardListTransactions);
router.post('/broadcast', adminDashboardBroadcast);
router.get('/topup-requests', adminDashboardListTopups);
router.patch('/topup-requests/:id/review', adminDashboardReviewTopup);
router.get('/analytics', adminDashboardAnalytics);
router.get('/reports', adminDashboardListReports);
router.patch('/reports/:id', adminDashboardResolveReport);
router.get('/quests', adminDashboardListQuests);
router.post('/quests', adminDashboardCreateQuest);
router.patch('/quests/:id', adminDashboardUpdateQuest);
router.delete('/quests/:id', adminDashboardDeleteQuest);
router.get('/leaderboard', adminDashboardLeaderboard);

export default router;
