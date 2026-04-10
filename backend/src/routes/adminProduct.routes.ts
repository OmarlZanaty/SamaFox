import { Router } from "express";
import multer from "multer";
import prisma from "../utils/prisma";
import { createProduct } from "../controllers/adminProduct.controller";
import { authMiddleware } from "../middlewares/auth.middleware";

const router = Router();

const adminMiddleware = async (req: any, res: any, next: any) => {
  const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { isAdmin: true } });
  if (!user?.isAdmin) {
    return res.status(403).json({ success: false, message: "Access denied. Admin only." });
  }
  return next();
};

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, "uploads/"),
  filename: (_req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});

const upload = multer({ storage });

router.post("/products", authMiddleware, adminMiddleware, upload.single("file"), createProduct);

export default router;
