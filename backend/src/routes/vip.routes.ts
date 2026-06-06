import { Router } from 'express';
import prisma from '../utils/prisma';
import { vipThreshold } from '../services/vip.service';

const router = Router();

// Public: VIP level catalog (badge image + seat frame + threshold per level).
// The app uses this to render a user's VIP badge from their vipLevel.
router.get('/levels', async (_req, res) => {
  try {
    const configs = await prisma.vipLevelConfig.findMany({ orderBy: { level: 'asc' } });
    const data = configs.map((c) => ({
      level: c.level,
      name: c.name,
      threshold: c.threshold ?? vipThreshold(c.level),
      badgeUrl: c.badgeUrl,
      frameItemId: c.frameItemId,
    }));
    return res.json({ success: true, data });
  } catch (e) {
    console.error('vip levels error:', e);
    return res.status(500).json({ success: false, message: 'Failed to load VIP levels' });
  }
});

export default router;
