// File: src/controllers/music.controller.ts
//
// Personal music library. The owner asked for: upload a song from the phone,
// see the songs you already uploaded, and delete one only when YOU choose to.
// Playback itself is not here — that is relayed live over the socket
// (`music_*` events in socket.service.ts) so the whole room hears the same
// track at the same position.

import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs/promises';
import prisma from '../utils/prisma';

const MUSIC_DIR = path.join(process.cwd(), 'uploads', 'music');

/** Hard cap so one user cannot fill the disk with a thousand songs. */
const MAX_TRACKS_PER_USER = 50;

function serialize(t: any) {
  return {
    id: t.id,
    title: t.title,
    url: t.url,
    filename: t.filename,
    sizeBytes: t.sizeBytes ?? 0,
    createdAt: t.createdAt,
  };
}

export async function listMyTracks(req: Request, res: Response) {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const tracks = await (prisma as any).musicTrack.findMany({
      where: { userId },
      orderBy: { createdAt: 'asc' },
    });

    return res.json({ success: true, tracks: tracks.map(serialize) });
  } catch (e) {
    console.error('listMyTracks error:', e);
    return res.status(500).json({ success: false, message: 'تعذر تحميل الأغاني' });
  }
}

export async function uploadTrack(req: Request, res: Response) {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    if (!req.file) return res.status(400).json({ success: false, message: 'لم يتم اختيار ملف' });

    const count = await (prisma as any).musicTrack.count({ where: { userId } });
    if (count >= MAX_TRACKS_PER_USER) {
      await fs.unlink(req.file.path).catch(() => {});
      return res.status(400).json({
        success: false,
        message: `الحد الأقصى ${MAX_TRACKS_PER_USER} أغنية. احذف أغنية قديمة أولاً`,
      });
    }

    // The client sends the real song name in `title`; the stored filename is
    // deliberately random so two users uploading "song.mp3" don't collide.
    const rawTitle = (req.body?.title ?? '').toString().trim();
    const fallback = path.parse(req.file.originalname || 'أغنية').name;
    const title = (rawTitle || fallback || 'أغنية').slice(0, 120);

    // Relative URL: the app prefixes the API host, so the same row keeps
    // working after the server moves (GCP → AWS).
    const url = `/uploads/music/${req.file.filename}`;

    const track = await (prisma as any).musicTrack.create({
      data: {
        userId,
        title,
        url,
        filename: req.file.filename,
        sizeBytes: Math.min(req.file.size ?? 0, 2_147_483_647),
      },
    });

    return res.status(201).json({ success: true, track: serialize(track) });
  } catch (e) {
    console.error('uploadTrack error:', e);
    return res.status(500).json({ success: false, message: 'فشل رفع الأغنية' });
  }
}

export async function deleteTrack(req: Request, res: Response) {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ success: false, message: 'معرّف غير صالح' });
    }

    const track = await (prisma as any).musicTrack.findUnique({ where: { id } });
    if (!track || track.userId !== userId) {
      return res.status(404).json({ success: false, message: 'الأغنية غير موجودة' });
    }

    await (prisma as any).musicTrack.delete({ where: { id } });

    // Never let a crafted filename escape the music directory.
    const safeName = path.basename(track.filename ?? '');
    if (safeName) {
      const filePath = path.join(MUSIC_DIR, safeName);
      if (path.normalize(filePath).startsWith(path.normalize(MUSIC_DIR + path.sep))) {
        await fs.unlink(filePath).catch(() => {});
      }
    }

    return res.json({ success: true, message: 'تم حذف الأغنية' });
  } catch (e) {
    console.error('deleteTrack error:', e);
    return res.status(500).json({ success: false, message: 'تعذر حذف الأغنية' });
  }
}
