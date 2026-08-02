import { Router } from 'express';
import prisma from '../utils/prisma';
import { vipThreshold, getVipThresholdOverrides, vipThresholdWithOverrides } from '../services/vip.service';
import { getLevelThresholdOverrides, levelThresholdWithOverrides } from '../services/xp.service';
import { grantVipRewardsForRange } from '../services/vip.service';
import { createNotification } from '../services/notification.service';
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

/**
 * Buy a VIP tier outright (owner request). The tier must have a priceCoins set
 * from the dashboard; durationDays null means the purchase never lapses.
 *
 * Buying grants exactly the same rewards as earning the tier, through the same
 * function, so a bought VIP 1 hands over the frame, entrance, badge and bubble
 * configured on it. Buying a tier at or below the one already held is refused
 * rather than silently charging for nothing.
 */
router.post('/buy', authMiddleware, async (req, res) => {
  try {
    const userId = (req as any).userId as number;
    const level = Number((req.body as any)?.level);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    if (!Number.isInteger(level) || level <= 0) {
      return res.status(400).json({ success: false, message: 'level مطلوب' });
    }

    const cfg: any = await prisma.vipLevelConfig.findUnique({ where: { level } });
    if (!cfg || cfg.priceCoins == null || cfg.priceCoins <= 0) {
      return res.status(404).json({ success: false, message: 'هذا المستوى غير معروض للبيع' });
    }

    const result = await prisma.$transaction(async (tx) => {
      const user = await tx.user.findUnique({
        where: { id: userId },
        select: { coinsBalance: true, vipLevel: true, vipExpiresAt: true },
      });
      if (!user) return { ok: false as const, status: 404, message: 'المستخدم غير موجود' };
      if (user.vipLevel >= level) {
        return { ok: false as const, status: 400, message: 'أنت بالفعل في هذا المستوى أو أعلى' };
      }
      if (user.coinsBalance < cfg.priceCoins) {
        return { ok: false as const, status: 400, message: 'الرصيد غير كافٍ' };
      }

      // Extend from whatever term is still running, so consecutive purchases
      // add up instead of resetting the clock.
      const base = (user as any).vipExpiresAt
        ? new Date(Math.max(Date.now(), new Date((user as any).vipExpiresAt).getTime()))
        : new Date();
      const expiresAt = cfg.durationDays
        ? new Date(base.getTime() + Number(cfg.durationDays) * 24 * 60 * 60 * 1000)
        : null;

      await tx.user.update({
        where: { id: userId },
        data: {
          coinsBalance: { decrement: cfg.priceCoins },
          vipLevel: level,
          vipExpiresAt: expiresAt,
        } as any,
      });
      return { ok: true as const, previousLevel: user.vipLevel, expiresAt };
    });

    if (!result.ok) return res.status(result.status).json({ success: false, message: result.message });

    // Outside the transaction: granting touches many rows and must not hold
    // the coin deduction open.
    await grantVipRewardsForRange(userId, result.previousLevel, level).catch((e) =>
      console.warn('[vip.buy] reward grant failed:', e),
    );
    await createNotification({
      userId,
      type: 'vip_level_up',
      title: 'ترقية VIP 👑',
      body: `تهانينا! أصبحت VIP ${level}`,
      data: { vipLevel: level, purchased: true },
    }).catch(() => {});

    return res.json({ success: true, vipLevel: level, expiresAt: result.expiresAt ?? null });
  } catch (e) {
    console.error('vip buy error:', e);
    return res.status(500).json({ success: false, message: 'فشل شراء VIP' });
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
      // null price = not for sale; null duration on a sellable tier = permanent.
      priceCoins: (c as any).priceCoins ?? null,
      durationDays: (c as any).durationDays ?? null,
    }));
    return res.json({ success: true, data });
  } catch (e) {
    console.error('vip levels error:', e);
    return res.status(500).json({ success: false, message: 'Failed to load VIP levels' });
  }
});

export default router;
