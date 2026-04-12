import { Router } from 'express';
import { authMiddleware as auth } from '../middlewares/auth.middleware';
import * as R from './relation.controller';

const router = Router();

router.post('/request/:userId', auth, R.sendRelationRequest);
router.get('/requests', auth, R.getPendingRelationRequests);
router.patch('/:id/respond', auth, R.respondToRelation);
router.delete('/:id', auth, R.endRelation);
router.get('/my', auth, R.getMyRelation);

export default router;
