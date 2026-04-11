import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import * as A from './agency.controller';

const router = Router();

router.get('/charging', A.listChargingAgencies);
router.get('/hosting', A.listHostingAgencies);
router.post('/request', authMiddleware, A.requestAgency);
router.get('/my-agency', authMiddleware, A.getMyAgency);
router.post('/send-coins', authMiddleware, A.sendCoinsToUser);
router.post('/invite/:userId', authMiddleware, A.inviteMember);
router.post('/invite/:inviteId/respond', authMiddleware, A.respondInvite);
router.get('/my-invites', authMiddleware, A.getMyInvites);

export default router;
