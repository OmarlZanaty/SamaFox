import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { uploadImage, uploadAvatar, uploadVideoAsset, deleteImage } from '../controllers/upload.controller';
import { authenticate } from '../middlewares/auth.middleware';
import { MAX_DASHBOARD_VIDEO_BYTES } from '../gifts/videoValidate';

const router = express.Router();

// Create uploads directory if it doesn't exist
const uploadsDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
  console.log('📁 Created uploads directory:', uploadsDir);
}

// ✅ FIX: map allowed MIME types to safe extensions — never trust the original extension
const ALLOWED_IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
};

// Configure multer storage
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (_req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    // ✅ FIX: force extension from MIME type — ignore file.originalname extension entirely
    const ext = ALLOWED_IMAGE_TYPES[file.mimetype] ?? '.bin';
    cb(null, `upload-${uniqueSuffix}${ext}`);
  }
});

// ✅ FIX: add fileFilter — reject anything not in the allowed MIME map
const fileFilter: multer.Options['fileFilter'] = (_req, file, cb) => {
  if (ALLOWED_IMAGE_TYPES[file.mimetype]) {
    cb(null, true);
  } else {
    cb(new Error(`Unsupported file type: ${file.mimetype}. Only JPEG, PNG, WebP and GIF are allowed.`));
  }
};

// Configure multer with file size limit and type validation
const upload = multer({
  storage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  },
  fileFilter,
});

// Video uploads (gift animations): separate multer with video MIME map + bigger limit
const ALLOWED_VIDEO_TYPES: Record<string, string> = {
  'video/mp4': '.mp4',
  'video/webm': '.webm',
  'video/quicktime': '.mov',
};

const videoStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadsDir),
  filename: (_req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = ALLOWED_VIDEO_TYPES[file.mimetype] ?? '.bin';
    cb(null, `upload-${uniqueSuffix}${ext}`);
  },
});

const uploadVideoMulter = multer({
  storage: videoStorage,
  limits: { fileSize: MAX_DASHBOARD_VIDEO_BYTES },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_VIDEO_TYPES[file.mimetype]) cb(null, true);
    else cb(new Error(`Unsupported video type: ${file.mimetype}. Only MP4, WebM and MOV are allowed.`));
  },
});

router.post('/avatar', authenticate, upload.single('avatar'), uploadAvatar);
router.post('/image', authenticate, upload.single('image'), uploadImage);
// Gift clips go through uploadVideoAsset (not uploadImage) so the file is probed
// and the caller gets back the real duration + alpha flag.
router.post('/video', authenticate, uploadVideoMulter.single('video'), uploadVideoAsset);
router.delete('/image/:filename', authenticate, deleteImage);

// A rejected file (wrong type, too large) used to bubble up as a bare 500, so the
// dashboard showed "Internal Server Error" instead of the real reason.
router.use((err: any, _req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (!err) return next();
  if (err instanceof multer.MulterError) {
    const message =
      err.code === 'LIMIT_FILE_SIZE'
        ? `حجم الملف أكبر من ${Math.round(MAX_DASHBOARD_VIDEO_BYTES / 1024 / 1024)} ميجابايت`
        : err.message;
    return res.status(400).json({ success: false, message });
  }
  return res.status(400).json({ success: false, message: err.message || 'فشل رفع الملف' });
});

export default router;