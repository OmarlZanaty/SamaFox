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
router.get('/search-user', authMiddleware, A.searchUserForInvite);
router.get('/members-stats', authMiddleware, A.getMembersStats);
router.get('/my-membership', authMiddleware, A.getMyMembership);
router.delete('/members/:userId', authMiddleware, A.removeMember);
router.patch('/exit-settings', authMiddleware, A.setExitSettings);
router.post('/leave', authMiddleware, A.leaveAgency);
router.post('/transfer-ownership', authMiddleware, A.transferOwnership);
router.post('/:agencyId/join-request', authMiddleware, A.requestJoinHostingAgency);
router.get('/join-requests/my-agency', authMiddleware, A.listMyAgencyJoinRequests);
router.patch('/join-requests/:inviteId/review', authMiddleware, A.reviewJoinRequest);

export default router;
