import type { Request, Response } from 'express';
import prisma from '../utils/prisma';

// Professional defaults (Yalla/Bigo-style) used until the client provides a real CP spec.
export const CP_DEFAULTS: Record<string, string> = {
  cp_per_coin: '1',              // CP earned per coin spent on a CP-eligible gift
  target_coins_per_dollar: '10000', // received-gift coins equal to $1 of target payout
  level_multiplier: '1.5',       // each level threshold = previous * this
  room_background_price_coins: '1000', // device-uploaded room background: price
  room_background_days: '20',          // …and how long it lasts before reverting

  // ── Forced update ────────────────────────────────────────────────────────
  // `min_supported_build` is the oldest build number allowed to keep running.
  // A device on anything lower is shown a blocking screen and sent to Play.
  //
  // 0 disables the gate entirely, which is the default ON PURPOSE: a wrong
  // value here locks every user out of the app at once, and that must be a
  // deliberate act, never something that happens because a row was missing.
  //
  // Set it to the build you are shipping only AFTER that build is live on
  // Play — set it first and you lock people out with nowhere to go.
  min_supported_build: '0',
  update_title: 'تحديث جديد متاح',
  update_message: 'نزّل آخر إصدار من سما فوكس عشان تكمل. فيه مزايا جديدة وإصلاحات في الصوت والغرف.',
  update_store_url: 'https://play.google.com/store/apps/details?id=com.almobarmg.samafox',

  // ── Voice engine ────────────────────────────────────────────────────────────────────────
  // `mesh`    — the original peer-to-peer full mesh (every phone connects to
  //             every other phone). Works up to a handful of people per room.
  // `livekit` — an SFU: every phone holds ONE connection, to the LiveKit
  //             server, which forwards audio. Rooms of 30+ become possible.
  //
  // A runtime switch rather than a build flag so a problem with the new engine
  // is rolled back by changing one row, not by shipping an app update. Clients
  // read it on launch; a room is entered with whatever engine was read.
  voice_engine: 'mesh',
  // Where the app connects for `livekit`. ws:// or wss://. Empty = engine
  // stays `mesh` regardless of the flag, so a half-configured server cannot
  // strand anyone.
  livekit_url: '',
  // ── صلاحيات فتح CP (2026-09-22) ──────────────────────────────────────────
  // The system policy for opening CP (couple pairing). `free` is exactly the
  // behaviour that existed before the permission system, so nothing changes
  // for anyone until an admin switches it. Edited from the CP panel; the
  // authoritative reader is cpUnlock.service.readCpSettings.
  cp_unlock_mode: 'free', // free | fee
  cp_unlock_fee_coins: '0',
  cp_level_step_coins: '0', // "قيمة رفع مستوى CP": 0 = days-based ladder
  cp_level_max: '5',
  cp_level_names: '',
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
    const s = await readSettings();
    return res.json({
      success: true,
      data: {
        ...s,
        // camelCase aliases for the app, which quotes the background price and
        // term to the room owner before charging them.
        roomBackgroundPriceCoins: Number(s.room_background_price_coins) || 1000,
        roomBackgroundDays: Number(s.room_background_days) || 20,
        // The update gate, camelCased for the app. Sent to everyone, including
        // signed-out devices, because the check runs before login.
        minSupportedBuild: Number(s.min_supported_build) || 0,
        updateTitle: s.update_title,
        updateMessage: s.update_message,
        updateStoreUrl: s.update_store_url,
        // Voice engine selection (see CP_DEFAULTS). The URL is what the app
        // dials; the key/secret never leave the server — the app gets a
        // short-lived token from /voice/token instead.
        voiceEngine: s.livekit_url ? s.voice_engine : 'mesh',
        livekitUrl: s.livekit_url,
      },
    });
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
