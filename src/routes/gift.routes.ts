import { Router } from 'express';
import { getGifts, sendGift, getGiftHistory } from '../controllers/gift.controller';
import { authMiddleware } from '../middlewares/auth.middleware';
import { giftLimiter } from '../middlewares/giftLimiter';

const router = Router();

router.get('/', getGifts);
router.post('/send', authMiddleware, sendGift);
router.get('/history', authMiddleware, getGiftHistory);
router.post("/sendGift", giftLimiter, sendGift);
export default router;
