// Dashboard «قوائم الإيموجي»: add / edit / delete lists and emoji, like gifts.
import { Router, Request, Response } from 'express';
import multer from 'multer';
import path from 'path';
import os from 'os';
import prisma from '../utils/prisma';
import { authMiddleware } from '../middlewares/auth.middleware';
import { adminMiddleware } from '../middlewares/admin.middleware';
import { uploadIcon } from '../gifts/admin.controller';
import { invalidateEmojiLists } from './emoji.service';

const upload = multer({ dest: path.join(os.tmpdir(), 'gift-uploads'), limits: { fileSize: 4 * 1024 * 1024 } });
const router = Router();
router.use(authMiddleware, adminMiddleware);

const str = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
const int = (v: unknown, d = 0) => (Number.isFinite(Number(v)) ? Math.floor(Number(v)) : d);

/** "12345, 678" (display IDs) → internal user ids; unknown IDs are reported back. */
export async function resolveUsers(raw: unknown): Promise<{ ids: number[]; missing: string[] }> {
  const tokens = (Array.isArray(raw) ? raw.map(String) : String(raw ?? '').split(/[\s,،]+/))
    .map((t) => t.trim())
    .filter(Boolean);
  const ids: number[] = [];
  const missing: string[] = [];
  for (const t of [...new Set(tokens)]) {
    const n = Number(t);
    const u = Number.isInteger(n) && n > 0
      ? await prisma.user.findUnique({ where: { displayId: n }, select: { id: true } })
      : null;
    if (u) ids.push(u.id);
    else missing.push(t);
  }
  return { ids: [...new Set(ids)], missing };
}

function wrap(fn: (req: Request, res: Response) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    try {
      await fn(req, res);
    } catch (err: any) {
      if (err?.code === 'P2025' || err?.code === 'P2003') {
        return res.status(404).json({ success: false, message: 'غير موجود' });
      }
      console.error('[admin.emoji]', err);
      return res.status(500).json({ success: false, message: 'فشلت العملية' });
    }
  };
}

router.get('/lists', wrap(async (_req, res) => {
  const lists = await prisma.emojiList.findMany({
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    include: { emojis: { orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] } },
  });
  const ids = [...new Set(lists.flatMap((l) => l.userIds))];
  const users = ids.length
    ? await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, displayId: true, name: true } })
    : [];
  const byId = new Map(users.map((u) => [u.id, u]));
  res.json({
    success: true,
    data: lists.map((l) => ({ ...l, users: l.userIds.map((id) => byId.get(id) ?? { id, displayId: null, name: '' }) })),
  });
}));

router.post('/lists', wrap(async (req, res) => {
  const nameAr = str(req.body?.nameAr);
  if (!nameAr) return res.status(400).json({ success: false, message: 'اكتب اسم القائمة' });
  const { ids, missing } = await resolveUsers(req.body?.userIds);
  const list = await prisma.emojiList.create({
    data: {
      nameAr,
      imageUrl: str(req.body?.imageUrl) || null,
      sortOrder: int(req.body?.sortOrder),
      minVip: Math.max(0, int(req.body?.minVip)),
      userIds: ids,
    },
  });
  invalidateEmojiLists();
  res.status(201).json({ success: true, data: list, missing });
}));

router.patch('/lists/:id', wrap(async (req, res) => {
  const b = req.body ?? {};
  const data: Record<string, unknown> = {};
  if (b.nameAr !== undefined) {
    if (!str(b.nameAr)) return res.status(400).json({ success: false, message: 'اكتب اسم القائمة' });
    data.nameAr = str(b.nameAr);
  }
  if (b.imageUrl !== undefined) data.imageUrl = str(b.imageUrl) || null;
  if (b.sortOrder !== undefined) data.sortOrder = int(b.sortOrder);
  if (b.isActive !== undefined) data.isActive = !!b.isActive;
  if (b.minVip !== undefined) data.minVip = Math.max(0, int(b.minVip));
  let missing: string[] = [];
  if (b.userIds !== undefined) {
    const r = await resolveUsers(b.userIds);
    data.userIds = r.ids;
    missing = r.missing;
  }
  const list = await prisma.emojiList.update({ where: { id: int(req.params.id) }, data });
  invalidateEmojiLists();
  res.json({ success: true, data: list, missing });
}));

router.delete('/lists/:id', wrap(async (req, res) => {
  await prisma.emojiList.delete({ where: { id: int(req.params.id) } });
  invalidateEmojiLists();
  res.json({ success: true });
}));

router.post('/lists/:id/emojis', wrap(async (req, res) => {
  const imageUrl = str(req.body?.imageUrl);
  if (!imageUrl) return res.status(400).json({ success: false, message: 'ارفع صورة الإيموجي' });
  const emoji = await prisma.emojiItem.create({
    data: { listId: int(req.params.id), name: str(req.body?.name), imageUrl, sortOrder: int(req.body?.sortOrder) },
  });
  invalidateEmojiLists();
  res.status(201).json({ success: true, data: emoji });
}));

router.patch('/emojis/:id', wrap(async (req, res) => {
  const b = req.body ?? {};
  const data: Record<string, unknown> = {};
  if (b.name !== undefined) data.name = str(b.name);
  if (b.imageUrl !== undefined && str(b.imageUrl)) data.imageUrl = str(b.imageUrl);
  if (b.sortOrder !== undefined) data.sortOrder = int(b.sortOrder);
  if (b.isActive !== undefined) data.isActive = !!b.isActive;
  if (b.listId !== undefined) data.listId = int(b.listId);
  const emoji = await prisma.emojiItem.update({ where: { id: int(req.params.id) }, data });
  invalidateEmojiLists();
  res.json({ success: true, data: emoji });
}));

router.delete('/emojis/:id', wrap(async (req, res) => {
  await prisma.emojiItem.delete({ where: { id: int(req.params.id) } });
  invalidateEmojiLists();
  res.json({ success: true });
}));

// PNG / WebP / GIF (an animated GIF stays animated), 256 px — the gift icon pipeline.
router.post('/upload', upload.single('file'), uploadIcon);

export default router;
