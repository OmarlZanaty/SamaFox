import { Router } from "express";
import multer from "multer";
import { createProduct } from "../controllers/adminProduct.controller";
import { authMiddleware } from '../middlewares/auth.middleware';
import { adminMiddleware } from '../middlewares/admin.middleware';

const router = Router();

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, "uploads/"),
  filename: (_req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});

const upload = multer({ storage });

router.post('/products', authMiddleware, adminMiddleware, upload.single('file'), createProduct);

export default router;
