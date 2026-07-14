import type { Request, Response } from 'express';
import prisma from '../utils/prisma';

// Professional defaults (Yalla/Bigo-style) used until the client provides a real CP spec.
export const CP_DEFAULTS: Record<string, string> = {
  cp_per_coin: '1',              // CP earned per coin spent on a CP-eligible gift
  target_coins_per_dollar: '10000', // received-gift coins equal to $1 of target payout
  level_multiplier: '1.5',       // each level threshold = previous * this
};

/** Read all app settings merged over the defaults. */
export async function readSettings(): Promise<Record<string, string>> {
  const rows = await prisma.appSetting.findMany();
  const merged: Record<string, string> = { ...CP_DEFAULTS };
  for (const r of rows) merged[r.key] = r.value;
  return merged;
}

/** Numeric CP config used by the gift/target logic. */
export async function getCpConfig() {
  const s = await readSettings();
  return {
    cpPerCoin: Number(s.cp_per_coin) || 1,
    targetCoinsPerDollar: Number(s.target_coins_per_dollar) || 10000,
    levelMultiplier: Number(s.level_multiplier) || 1.5,
  };
}

// GET /settings  — public read (clients need target/payout rates to render progress).
export async function getSettings(_req: Request, res: Response) {
  try {
    return res.json({ success: true, data: await readSettings() });
  } catch (e) {
    console.error('[settings.getSettings]', e);
    return res.status(500).json({ success: false, message: 'Failed to load settings' });
  }
}

// PATCH /admin/settings  — admin upserts one or more keys. Body: { key: value, ... }
export async function updateSettings(req: Request, res: Response) {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const entries = Object.entries(body).filter(([k]) => typeof k === 'string' && k.length > 0);
    if (entries.length === 0) return res.status(400).json({ success: false, message: 'No settings provided' });

    await prisma.$transaction(
      entries.map(([key, value]) =>
        prisma.appSetting.upsert({
          where: { key },
          update: { value: String(value) },
          create: { key, value: String(value) },
        }),
      ),
    );
    return res.json({ success: true, data: await readSettings() });
  } catch (e) {
    console.error('[settings.updateSettings]', e);
    return res.status(500).json({ success: false, message: 'Failed to update settings' });
  }
}
