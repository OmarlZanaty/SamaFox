import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import * as A from './agency.controller';

const router = Router();

router.get('/charging', A.listChargingAgencies);
router.get('/hosting', A.listHostingAgencies);
router.post('/request', authMiddleware, A.requestAgency);
router.get('/my-agency', authMiddleware, A.getMyAgency);
router.post('/send-coins', authMiddleware, A.sendCoinsToUser);
// Branch (فرع) management — owner adds/lists/removes partners who can also sell coins.
router.get('/branches', authMiddleware, A.listBranches);
router.post('/branches', authMiddleware, A.addBranch);
router.delete('/branches/:userId', authMiddleware, A.removeBranch);
router.post('/invite/:userId', authMiddleware, A.inviteMember);
router.post('/invite/:inviteId/respond', authMiddleware, A.respondInvite);
router.get('/my-invites', authMiddleware, A.getMyInvites);
router.get('/search-user', authMiddleware, A.searchUserForInvite);
router.get('/members-stats', authMiddleware, A.getMembersStats);
// Target system (#13, #24)
router.get('/my-target', authMiddleware, A.getMyTarget);
router.patch('/members/:userId/target', authMiddleware, A.setMemberTarget);
router.get('/my-membership', authMiddleware, A.getMyMembership);
router.get('/my-memberships', authMiddleware, A.getMyMemberships);
router.delete('/members/:userId', authMiddleware, A.removeMember);
router.patch('/exit-settings', authMiddleware, A.setExitSettings);
router.post('/leave', authMiddleware, A.leaveAgency);
router.post('/transfer-ownership', authMiddleware, A.transferOwnership);
router.post('/:agencyId/join-request', authMiddleware, A.requestJoinHostingAgency);
router.get('/join-requests/my-agency', authMiddleware, A.listMyAgencyJoinRequests);
router.patch('/join-requests/:inviteId/review', authMiddleware, A.reviewJoinRequest);

export default router;
