import { Router } from 'express';
import { authMiddleware as auth } from '../middlewares/auth.middleware';
import * as F from './follow.controller';

const router = Router();

router.post('/:userId', auth, F.sendFollowRequest);
router.patch('/:followId/respond', auth, F.respondToFollow);
router.delete('/:userId', auth, F.unfollow);
router.delete('/remove/:userId', auth, F.removeFollower);
router.get('/followers', auth, F.getFollowers);
router.get('/following', auth, F.getFollowing);
router.get('/requests', auth, F.getPendingRequests);
router.get('/status/:userId', auth, F.getFollowStatus);

export default router;
