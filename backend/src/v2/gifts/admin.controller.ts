import type { Request, Response } from 'express';
import path from 'path';
import fs from 'fs/promises';
import prisma from '../../utils/prisma';
import { sanitizeGiftHtml, MAX_HTML_BYTES } from './sanitize';
import { bumpCatalogVersion } from './catalogCache';
import { recordGiftAudit } from './audit';
import { validateGiftVideo, isAllowedVideoExtension, MAX_VIDEO_BYTES } from './videoValidate';
import { GIFT_TEMPLATES } from './templates';

const ASSETS_DIR =
  process.env.GIFT_ASSETS_DIR?.trim() || path.join(process.cwd(), 'public', 'assets');
const VIDEOS_DIR = path.join(ASSETS_DIR, 'videos');
const ICONS_DIR = path.join(ASSETS_DIR, 'icons');

async function ensureDir(dir: string) {
  await fs.mkdir(dir, { recursive: true });
}

const TIERS = new Set(['SMALL', 'MEDIUM', 'LARGE', 'LEGENDARY']);
const FORMATS = new Set(['SVG_CSS', 'VIDEO']);

interface GiftWriteInput {
  name?: string;
  nameAr?: string | null;
  iconUrl?: string;
  format?: 'SVG_CSS' | 'VIDEO';
  animationHtml?: string | null;
  animationUrl?: string | null;
  videoHasAlpha?: boolean;
  fireworksEnabled?: boolean;
  fireworksColors?: unknown;
  coinCost?: number;
  tier?: 'SMALL' | 'MEDIUM' | 'LARGE' | 'LEGENDARY';
  animationMs?: number;
  isComboEligible?: boolean;
  broadcastGlobal?: boolean;
  isActive?: boolean;
  sortOrder?: number;
  category?: string | null;
}

function normalize(input: GiftWriteInput, existing?: any) {
  const out: any = { ...existing };
  if (input.name !== undefined) out.name = String(input.name).trim();
  if (input.nameAr !== undefined) out.nameAr = input.nameAr ? String(input.nameAr).trim() : null;
  if (input.iconUrl !== undefined) out.iconUrl = String(input.iconUrl).trim();
  if (input.format !== undefined) out.format = input.format;
  if (input.animationHtml !== undefined) out.animationHtml = input.animationHtml;
  if (input.animationUrl !== undefined) out.animationUrl = input.animationUrl;
  if (input.videoHasAlpha !== undefined) out.videoHasAlpha = !!input.videoHasAlpha;
  if (input.fireworksEnabled !== undefined) out.fireworksEnabled = !!input.fireworksEnabled;
  if (input.fireworksColors !== undefined) out.fireworksColors = input.fireworksColors ?? null;
  if (input.coinCost !== undefined) out.coinCost = Math.max(0, Math.floor(Number(input.coinCost)));
  if (input.tier !== undefined) out.tier = input.tier;
  if (input.animationMs !== undefined) out.animationMs = Math.max(500, Math.floor(Number(input.animationMs)));
  if (input.isComboEligible !== undefined) out.isComboEligible = !!input.isComboEligible;
  if (input.broadcastGlobal !== undefined) out.broadcastGlobal = !!input.broadcastGlobal;
  if (input.isActive !== undefined) out.isActive = !!input.isActive;
  if (input.sortOrder !== undefined) out.sortOrder = Math.floor(Number(input.sortOrder)) || 0;
  if (input.category !== undefined) out.category = input.category ? String(input.category).trim() : null;
  return out;
}

function validateForWrite(payload: any): string | null {
  if (!payload.name) return 'name is required';
  if (!payload.iconUrl) return 'iconUrl is required';
  if (!FORMATS.has(payload.format)) return 'format must be SVG_CSS or VIDEO';
  if (!TIERS.has(payload.tier)) return 'tier must be SMALL, MEDIUM, LARGE, or LEGENDARY';
  if (payload.coinCost == null || payload.coinCost < 0) return 'coinCost must be >= 0';
  if (payload.format === 'SVG_CSS') {
    if (!payload.animationHtml) return 'animationHtml is required for SVG_CSS gifts';
  } else if (payload.format === 'VIDEO') {
    if (!payload.animationUrl) return 'animationUrl is required for VIDEO gifts';
  }
  if (payload.tier === 'LEGENDARY' && payload.format !== 'VIDEO') {
    return 'LEGENDARY tier requires VIDEO format';
  }
  return null;
}

export async function listAll(_req: Request, res: Response) {
  try {
    const gifts = await prisma.giftV2.findMany({
      orderBy: [{ tier: 'asc' }, { sortOrder: 'asc' }, { createdAt: 'desc' }],
    });
    return res.json({ success: true, total: gifts.length, gifts });
  } catch (err) {
    console.error('[admin.gifts.listAll]', err);
    return res.status(500).json({ success: false, message: 'Failed to list gifts' });
  }
}

export async function getOne(req: Request, res: Response) {
  try {
    const id = String(req.params.id);
    const gift = await prisma.giftV2.findUnique({ where: { id } });
    if (!gift) return res.status(404).json({ success: false, message: 'Not found' });
    return res.json({ success: true, gift });
  } catch (err) {
    console.error('[admin.gifts.getOne]', err);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
}

export async function create(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const data = normalize(req.body as GiftWriteInput);
    if (data.tier === 'LEGENDARY') data.broadcastGlobal = true;
    const reason = validateForWrite(data);
    if (reason) return res.status(400).json({ success: false, message: reason });

    if (data.format === 'SVG_CSS') {
      const sani = sanitizeGiftHtml(data.animationHtml);
      if (!sani.ok) return res.status(400).json({ success: false, message: sani.reason });
      data.animationHtml = sani.html;
    }
    data.createdBy = adminId;

    const gift = await prisma.giftV2.create({ data });
    await bumpCatalogVersion();
    await recordGiftAudit({ adminId, giftId: gift.id, action: 'CREATE', after: gift });
    return res.status(201).json({ success: true, gift });
  } catch (err: any) {
    console.error('[admin.gifts.create]', err);
    return res.status(500).json({ success: false, message: 'Create failed', detail: err?.message });
  }
}

export async function update(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const id = String(req.params.id);
    const before = await prisma.giftV2.findUnique({ where: { id } });
    if (!before) return res.status(404).json({ success: false, message: 'Not found' });

    const data = normalize(req.body as GiftWriteInput, before);
    if (data.tier === 'LEGENDARY') data.broadcastGlobal = true;
    const reason = validateForWrite(data);
    if (reason) return res.status(400).json({ success: false, message: reason });

    if (data.format === 'SVG_CSS' && (data.animationHtml !== before.animationHtml)) {
      const sani = sanitizeGiftHtml(data.animationHtml);
      if (!sani.ok) return res.status(400).json({ success: false, message: sani.reason });
      data.animationHtml = sani.html;
    }
    delete data.id;
    delete data.createdAt;
    delete data.updatedAt;

    const gift = await prisma.giftV2.update({ where: { id }, data });
    await bumpCatalogVersion();
    const action: any =
      before.isActive && !gift.isActive ? 'DEACTIVATE'
      : !before.isActive && gift.isActive ? 'ACTIVATE'
      : 'UPDATE';
    await recordGiftAudit({ adminId, giftId: gift.id, action, before, after: gift });
    return res.json({ success: true, gift });
  } catch (err: any) {
    console.error('[admin.gifts.update]', err);
    return res.status(500).json({ success: false, message: 'Update failed', detail: err?.message });
  }
}

export async function softDelete(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const id = String(req.params.id);
    const before = await prisma.giftV2.findUnique({ where: { id } });
    if (!before) return res.status(404).json({ success: false, message: 'Not found' });
    const gift = await prisma.giftV2.update({ where: { id }, data: { isActive: false } });
    await bumpCatalogVersion();
    await recordGiftAudit({ adminId, giftId: id, action: 'DELETE', before, after: gift });
    return res.json({ success: true });
  } catch (err) {
    console.error('[admin.gifts.softDelete]', err);
    return res.status(500).json({ success: false, message: 'Delete failed' });
  }
}

export async function preview(req: Request, res: Response) {
  try {
    const id = String(req.params.id);
    const gift = await prisma.giftV2.findUnique({ where: { id } });
    if (!gift) return res.status(404).json({ success: false, message: 'Not found' });
    if (gift.format !== 'SVG_CSS' || !gift.animationHtml) {
      return res.status(400).json({ success: false, message: 'Preview is only available for SVG_CSS gifts' });
    }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; img-src data:;");
    return res.send(gift.animationHtml);
  } catch (err) {
    console.error('[admin.gifts.preview]', err);
    return res.status(500).send('preview failed');
  }
}

export async function uploadVideo(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const file = (req as any).file as Express.Multer.File | undefined;
    if (!file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    if (!isAllowedVideoExtension(file.originalname)) {
      await fs.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, message: 'Only .mp4, .webm, .mov allowed' });
    }
    if (file.size > MAX_VIDEO_BYTES) {
      await fs.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, message: `Max size ${MAX_VIDEO_BYTES} bytes` });
    }
    let probe;
    try {
      probe = await validateGiftVideo(file.path);
    } catch (err: any) {
      await fs.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, message: err.message || 'Video validation failed' });
    }
    await ensureDir(VIDEOS_DIR);
    const target = path.join(VIDEOS_DIR, path.basename(file.path) + path.extname(file.originalname));
    await fs.rename(file.path, target);
    const url = `/assets/videos/${path.basename(target)}`;
    return res.json({
      success: true,
      url,
      duration: probe.durationMs / 1000,
      hasAlpha: probe.hasAlpha,
      fileSize: probe.fileSize,
      resolution: `${probe.width}x${probe.height}`,
      framerate: probe.framerate,
    });
  } catch (err) {
    console.error('[admin.gifts.uploadVideo]', err);
    return res.status(500).json({ success: false, message: 'Upload failed' });
  }
}

export async function uploadIcon(req: Request, res: Response) {
  try {
    const file = (req as any).file as Express.Multer.File | undefined;
    if (!file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    const ext = path.extname(file.originalname).toLowerCase();
    if (!['.png', '.jpg', '.jpeg', '.webp', '.svg'].includes(ext)) {
      await fs.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, message: 'Unsupported image type' });
    }
    if (file.size > 2 * 1024 * 1024) {
      await fs.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, message: 'Icon must be <= 2MB' });
    }
    await ensureDir(ICONS_DIR);
    const target = path.join(ICONS_DIR, path.basename(file.path) + ext);
    await fs.rename(file.path, target);
    return res.json({ success: true, url: `/assets/icons/${path.basename(target)}` });
  } catch (err) {
    console.error('[admin.gifts.uploadIcon]', err);
    return res.status(500).json({ success: false, message: 'Upload failed' });
  }
}

export async function reorder(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const items = (req.body?.items ?? []) as Array<{ id: string; sortOrder: number }>;
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, message: 'items array required' });
    }
    await prisma.$transaction(
      items.map((i) =>
        prisma.giftV2.update({
          where: { id: String(i.id) },
          data: { sortOrder: Math.floor(Number(i.sortOrder)) || 0 },
        }),
      ),
    );
    await bumpCatalogVersion();
    await recordGiftAudit({ adminId, action: 'REORDER', after: items });
    return res.json({ success: true });
  } catch (err) {
    console.error('[admin.gifts.reorder]', err);
    return res.status(500).json({ success: false, message: 'Reorder failed' });
  }
}

export async function bulkImport(req: Request, res: Response) {
  try {
    const adminId = req.userId!;
    const body = req.body ?? {};
    const gifts: any[] = Array.isArray(body.gifts) ? body.gifts : [];
    const mode: 'create' | 'upsert' = body.mode === 'upsert' ? 'upsert' : 'create';
    const dryRun = !!body.dryRun;
    if (gifts.length === 0) {
      return res.status(400).json({ success: false, message: 'gifts array required' });
    }
    const results: any[] = [];
    for (const raw of gifts) {
      const data = normalize(raw);
      if (data.tier === 'LEGENDARY') data.broadcastGlobal = true;
      const reason = validateForWrite(data);
      if (reason) {
        results.push({ name: raw?.name, ok: false, reason });
        continue;
      }
      if (data.format === 'SVG_CSS') {
        const s = sanitizeGiftHtml(data.animationHtml);
        if (!s.ok) {
          results.push({ name: raw?.name, ok: false, reason: s.reason });
          continue;
        }
        data.animationHtml = s.html;
      }
      data.createdBy = adminId;
      if (dryRun) {
        results.push({ name: data.name, ok: true, action: 'dry-run' });
        continue;
      }
      if (mode === 'upsert') {
        const existing = await prisma.giftV2.findFirst({ where: { name: data.name } });
        if (existing) {
          const updated = await prisma.giftV2.update({ where: { id: existing.id }, data });
          results.push({ name: data.name, ok: true, action: 'updated', id: updated.id });
          continue;
        }
      }
      const created = await prisma.giftV2.create({ data });
      results.push({ name: data.name, ok: true, action: 'created', id: created.id });
    }
    if (!dryRun) await bumpCatalogVersion();
    return res.json({ success: true, results });
  } catch (err) {
    console.error('[admin.gifts.bulkImport]', err);
    return res.status(500).json({ success: false, message: 'Import failed' });
  }
}

export async function exportAll(_req: Request, res: Response) {
  try {
    const gifts = await prisma.giftV2.findMany({ orderBy: [{ tier: 'asc' }, { sortOrder: 'asc' }] });
    res.setHeader('Content-Disposition', 'attachment; filename="gifts-v2.json"');
    return res.json({ version: '1.0', exportedAt: new Date(), gifts });
  } catch (err) {
    console.error('[admin.gifts.exportAll]', err);
    return res.status(500).json({ success: false, message: 'Export failed' });
  }
}

export async function auditLog(req: Request, res: Response) {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
    const skip = (page - 1) * limit;
    const [items, total] = await Promise.all([
      prisma.giftV2AdminAudit.findMany({ orderBy: { createdAt: 'desc' }, skip, take: limit }),
      prisma.giftV2AdminAudit.count(),
    ]);
    return res.json({ success: true, page, limit, total, items });
  } catch (err) {
    console.error('[admin.gifts.auditLog]', err);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
}

export async function listTemplates(_req: Request, res: Response) {
  return res.json({
    success: true,
    templates: GIFT_TEMPLATES.map((t) => ({
      key: t.key,
      name: t.name,
      nameAr: t.nameAr,
      tier: t.tier,
      category: t.category,
      coinCost: t.coinCost,
      animationMs: t.animationMs,
      htmlSize: Buffer.byteLength(t.html, 'utf8'),
    })),
  });
}

export async function getTemplate(req: Request, res: Response) {
  const key = String(req.params.key);
  const tpl = GIFT_TEMPLATES.find((t) => t.key === key);
  if (!tpl) return res.status(404).json({ success: false, message: 'Template not found' });
  return res.json({ success: true, template: tpl });
}

export const adminLimits = {
  htmlBytes: MAX_HTML_BYTES,
  videoBytes: MAX_VIDEO_BYTES,
};
