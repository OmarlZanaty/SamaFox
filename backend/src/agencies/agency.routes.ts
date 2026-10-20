import * as I from './agencyIdentity.controller';
import { Router } from 'express';
import { authMiddleware, optionalAuth } from '../middlewares/auth.middleware';
import * as A from './agency.controller';
import { idempotent } from '../middlewares/idempotency.middleware';

const router = Router();

// B8 — public, but identity-aware: an agency OWNER sees only his own agency,
// everyone else still sees the full list. optionalAuth never rejects.
router.get('/charging', optionalAuth, A.listChargingAgencies);
router.get('/hosting', optionalAuth, A.listHostingAgencies);
router.post('/request', authMiddleware, A.requestAgency);
router.get('/my-agency', authMiddleware, A.getMyAgency);
router.post('/send-coins', authMiddleware, idempotent('agency_send_coins'), A.sendCoinsToUser);
// Branch (فرع) management — owner adds/lists/removes partners who can also sell coins.
router.get('/branches', authMiddleware, A.listBranches);
router.post('/branches', authMiddleware, A.addBranch);
router.delete('/branches/:userId', authMiddleware, A.removeBranch);
router.post('/invite/:userId', authMiddleware, A.inviteMember);
// SPEC52 #35 — resend / cancel a still-pending invitation.
router.post('/invites/:inviteId/resend', authMiddleware, async (req: any, res) => {
  try {
    const { changePendingInvite } = await import('../services/agencyInvites.service');
    return res.json({ success: true, data: await changePendingInvite(req.userId, Number(req.params.inviteId), true) });
  } catch (e) {
    const { agencyError } = await import('./agencyIdentity.controller');
    return agencyError(res, e);
  }
});
router.post('/invites/:inviteId/cancel', authMiddleware, async (req: any, res) => {
  try {
    const { changePendingInvite } = await import('../services/agencyInvites.service');
    return res.json({ success: true, data: await changePendingInvite(req.userId, Number(req.params.inviteId), false) });
  } catch (e) {
    const { agencyError } = await import('./agencyIdentity.controller');
    return agencyError(res, e);
  }
});
// SPEC52 #35 — agency name / image (owner) + history.
router.patch('/:id/profile', authMiddleware, I.profile);
router.get('/:id/profile-history', authMiddleware, I.profileHistory);
// SPEC52 #36 — charging-agency branches, isolated per branch.
router.get('/:id/branches', authMiddleware, I.branches());
router.post('/:id/branches', authMiddleware, I.createBranch);
router.patch('/:id/branches/:branchId', authMiddleware, I.patchBranch());
router.get('/:id/branches/:branchId/transfers', authMiddleware, I.branchTransfers);
router.get('/:id/transfers', authMiddleware, I.branchTransfers);
router.post('/invite/:inviteId/respond', authMiddleware, idempotent('agency_invite_respond'), A.respondInvite);
router.get('/my-invites', authMiddleware, A.getMyInvites);
router.get('/search-user', authMiddleware, A.searchUserForInvite);
router.get('/members-stats', authMiddleware, A.getMembersStats);
// Target system (#13, #24)
router.get('/my-target', authMiddleware, A.getMyTarget);
router.post('/target/convert', authMiddleware, idempotent('target_convert'), A.convertTarget);
router.post('/target/sell', authMiddleware, idempotent('target_sell'), A.sellMemberTarget);
router.patch('/members/:userId/target', authMiddleware, A.setMemberTarget);
// وقت البث — days/hours on air for me, or for a member of my agency.
router.get('/broadcast-time', authMiddleware, A.getBroadcastTime);
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
