import { Router } from 'express';
import prisma from '../utils/prisma';
import { vipThreshold, getVipThresholdOverrides, vipThresholdWithOverrides } from '../services/vip.service';
import { getLevelThresholdOverrides, levelThresholdWithOverrides } from '../services/xp.service';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

// GET /vip/progress — for the tappable level / VIP rows on the profile (#23, #24).
// Returns how far the user is from the next level and the next VIP tier.
router.get('/progress', authMiddleware, async (req, res) => {
  try {
    const userId = (req as any).userId;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { level: true, xp: true, vipLevel: true, totalRecharge: true },
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const nextLevel = user.level + 1;
    // LV reads the SAME source as the promotion itself (LevelConfig via
    // xp.service), so the dialog can't promise a target that differs from the
    // rule that actually levels the user up — matching how VIP already works.
    const levelOverrides = await getLevelThresholdOverrides();
    const nextLevelXp = levelThresholdWithOverrides(nextLevel, levelOverrides);
    const nextVip = user.vipLevel + 1;
    const overrides = await getVipThresholdOverrides();
    const nextVipThreshold = vipThresholdWithOverrides(nextVip, overrides);

    return res.json({
      success: true,
      data: {
        level: user.level,
        xp: user.xp,
        nextLevel,
        xpForNextLevel: nextLevelXp,
        xpRemaining: Math.max(0, nextLevelXp - user.xp),
        vipLevel: user.vipLevel,
        totalRecharge: user.totalRecharge,
        nextVip,
        coinsForNextVip: nextVipThreshold,
        coinsRemainingForNextVip: Math.max(0, nextVipThreshold - user.totalRecharge),
      },
    });
  } catch (e) {
    console.error('vip progress error:', e);
    return res.status(500).json({ success: false, message: 'Failed to load progress' });
  }
});

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
