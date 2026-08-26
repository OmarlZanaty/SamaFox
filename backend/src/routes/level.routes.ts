import { Router } from 'express';
import prisma from '../utils/prisma';
import { levelThresholdWithOverrides } from '../services/xp.service';

const router = Router();

// Public: LV level catalog (badge image + name + XP threshold per level) — the
// exact counterpart of GET /vip/levels, so the app can render a user's المستوى
// badge from whatever the dashboard configured instead of a hardcoded chip.
// Empty list = nothing configured, and the app keeps its built-in look.
router.get('/', async (_req, res) => {
  try {
    const configs = await prisma.levelConfig.findMany({ orderBy: { level: 'asc' } });
    const data = configs.map((c) => ({
      level: c.level,
      name: c.name,
      threshold: c.threshold ?? levelThresholdWithOverrides(c.level, new Map()),
      badgeUrl: c.badgeUrl,
    }));
    return res.json({ success: true, data });
  } catch (e) {
    console.error('level catalog error:', e);
    return res.status(500).json({ success: false, message: 'Failed to load levels' });
  }
});

export default router;
