import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import { emojiListsFor } from './emoji.service';

const router = Router();

// The room emoji picker: the dashboard lists this user may open.
router.get('/lists', authMiddleware, async (req, res) => {
  try {
    return res.json({ success: true, data: await emojiListsFor(req.userId!) });
  } catch (err) {
    console.error('[emoji.lists]', err);
    return res.status(500).json({ success: false, message: 'Failed to load emoji' });
  }
});

export default router;
