import { Router } from 'express';
import { search } from './search.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();
router.use(authMiddleware); // ✅ auth goes here
router.get('/', search);

export default router;