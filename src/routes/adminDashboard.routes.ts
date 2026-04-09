import express from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import {
  adminDashboardOverview,
  adminDashboardListUsers,
  adminDashboardListRooms,
  adminDashboardListChargingAgencies,
  adminDashboardUpdateAgencyStatus
} from '../controllers/adminDashboard.controller';

const router = express.Router();

router.get('/overview', authenticate, adminDashboardOverview);
router.get('/users', authenticate, adminDashboardListUsers);
router.get('/rooms', authenticate, adminDashboardListRooms);
router.get('/charging-agencies', authenticate, adminDashboardListChargingAgencies);
router.patch('/charging-agencies/:id/status', authenticate, adminDashboardUpdateAgencyStatus);

export default router;
