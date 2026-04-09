import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import {
  listChargingAgencies,
  myChargingAgencies,
  createChargingAgency,
  myAgencyBalance,
  myAgencyTransfers,
  agencyTransferCoins,
  createTopupRequest,
  myTopupRequests,
  adminListTopups,
  reviewTopupRequest,
  adminAdjustAgencyBalance,
  updateChargingAgencyStatus,
} from '../controllers/charging-agency.controller';

const router = Router();

// Public
router.get('/', listChargingAgencies);

// Agent (auth)
router.get('/me', authMiddleware, myChargingAgencies);
router.post('/', authMiddleware, createChargingAgency);

router.get('/my/balance', authMiddleware, myAgencyBalance);
router.get('/my/transfers', authMiddleware, myAgencyTransfers);

router.post('/transfer', authMiddleware, agencyTransferCoins);

// Topups (agent)
router.post('/topup', authMiddleware, createTopupRequest);
router.get('/my/topups', authMiddleware, myTopupRequests);

// Admin
router.get('/admin/topups', authMiddleware, adminListTopups);
router.patch('/topup/:id/review', authMiddleware, reviewTopupRequest);

router.patch('/:id/balance', authMiddleware, adminAdjustAgencyBalance);
router.patch('/:id/status', authMiddleware, updateChargingAgencyStatus);

export default router;
