import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { uploadImage, uploadAvatar, deleteImage } from '../controllers/upload.controller';
import { authenticate } from '../middlewares/auth.middleware';

const router = express.Router();

// Create uploads directory if it doesn't exist
const uploadsDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
  console.log('📁 Created uploads directory:', uploadsDir);
}

// Configure multer storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const nameWithoutExt = path.basename(file.originalname, ext);
    const sanitizedName = nameWithoutExt.replace(/[^a-zA-Z0-9]/g, '_');
    cb(null, `${sanitizedName}-${uniqueSuffix}${ext}`);
  }
});

// Configure multer with file size limit
const upload = multer({
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  }
});

router.post('/avatar', authenticate, upload.single('avatar'), uploadAvatar);
router.post('/image', authenticate, upload.single('image'), uploadImage);
router.delete('/image/:filename', authenticate, deleteImage);

export default router;
