// File: src/routes/music.routes.ts
// Personal music library (upload / list / delete). Playback is relayed over
// the socket, see the `music_*` handlers in socket.service.ts.

import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { authenticate } from '../middlewares/auth.middleware';
import { listMyTracks, uploadTrack, deleteTrack } from '../controllers/music.controller';

const router = Router();

const musicDir = path.join(process.cwd(), 'uploads', 'music');
fs.mkdirSync(musicDir, { recursive: true });

// Extension comes from the MIME type, never from the uploaded name.
const ALLOWED_AUDIO_TYPES: Record<string, string> = {
  'audio/mpeg': '.mp3',
  'audio/mp3': '.mp3',
  'audio/mp4': '.m4a',
  'audio/x-m4a': '.m4a',
  'audio/aac': '.aac',
  'audio/aacp': '.aac',
  'audio/ogg': '.ogg',
  'audio/opus': '.opus',
  'audio/wav': '.wav',
  'audio/x-wav': '.wav',
  'audio/wave': '.wav',
  'audio/webm': '.weba',
  'audio/flac': '.flac',
  'audio/x-flac': '.flac',
};

// Some Android pickers hand over `application/octet-stream` for a perfectly
// normal mp3, so fall back to the original extension when the MIME is generic.
const ALLOWED_EXTENSIONS = new Set([
  '.mp3', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.weba', '.flac',
]);

function resolveExtension(file: Express.Multer.File): string | null {
  const byMime = ALLOWED_AUDIO_TYPES[file.mimetype];
  if (byMime) return byMime;
  const byName = path.extname(file.originalname || '').toLowerCase();
  return ALLOWED_EXTENSIONS.has(byName) ? byName : null;
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, musicDir),
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `music-${unique}${resolveExtension(file) ?? '.mp3'}`);
  },
});

const MAX_TRACK_BYTES = 25 * 1024 * 1024; // 25 MB — a normal song is 3–8 MB

const upload = multer({
  storage,
  limits: { fileSize: MAX_TRACK_BYTES },
  fileFilter: (_req, file, cb) => {
    if (resolveExtension(file)) cb(null, true);
    else cb(new Error('صيغة الملف غير مدعومة. اختر ملف صوتي (mp3, m4a, aac, wav, ogg)'));
  },
});

router.get('/tracks', authenticate, listMyTracks);
router.post('/tracks', authenticate, upload.single('audio'), uploadTrack);
router.delete('/tracks/:id', authenticate, deleteTrack);

// Turn a rejected upload into a readable message instead of a bare 500.
router.use((err: any, _req: any, res: any, next: any) => {
  if (!err) return next();
  if (err instanceof multer.MulterError) {
    const message =
      err.code === 'LIMIT_FILE_SIZE'
        ? `حجم الأغنية أكبر من ${Math.round(MAX_TRACK_BYTES / 1024 / 1024)} ميجابايت`
        : err.message;
    return res.status(400).json({ success: false, message });
  }
  return res.status(400).json({ success: false, message: err.message || 'فشل رفع الأغنية' });
});

export default router;
