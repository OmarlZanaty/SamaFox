import { Router } from 'express';
import { authMiddleware as auth } from '../middlewares/auth.middleware';
import * as F from './follow.controller';
import * as R from './relations.controller';

const router = Router();

// ✅ Static routes FIRST (before /:userId)
router.get('/followers', auth, F.getFollowers);
router.get('/following', auth, F.getFollowing);
router.get('/requests', auth, F.getPendingRequests);
router.delete('/remove/:userId', auth, F.removeFollower);

// ── C16: أصدقاء / أتابعه / يتابعني / الزوار ───────────────────────────────
// One call returns all three follow buckets — they are defined by each other,
// so fetching them separately lets the tabs contradict themselves mid-render.
router.get('/relations', auth, R.getRelations);
// الزوار: recorded only from the home page, read back newest-first.
router.post('/visits/:userId', auth, R.recordProfileVisit);
router.get('/visitors', auth, R.getMyVisitors);

// ✅ Parameter routes AFTER

router.post('/:userId', auth, F.sendFollowRequest);
router.patch('/:followId/respond', auth, F.respondToFollow);
router.delete('/:userId', auth, F.unfollow);
router.get('/status/:userId', auth, F.getFollowStatus);

export default router;
