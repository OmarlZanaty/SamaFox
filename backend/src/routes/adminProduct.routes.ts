import { Router } from "express";
import multer from "multer";
import prisma from "../utils/prisma";
import { createProduct } from "../controllers/adminProduct.controller";
import { authMiddleware } from "../middlewares/auth.middleware";

const router = Router();

const adminMiddleware = async (req: any, res: any, next: any) => {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { isAdmin: true } });
    if (!user?.isAdmin) {
      return res.status(403).json({ success: false, message: "Access denied. Admin only." });
    }
    return next();
  } catch (error) {
    console.error("adminMiddleware error:", error);
    return res.status(500).json({ success: false, message: "Server error" });
  }
};

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, "uploads/"),
  filename: (_req, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, "_");
    cb(null, `${Date.now()}-${safeName}`);
  },
});

const upload = multer({ storage });

router.post("/products", authMiddleware, adminMiddleware, upload.single("file"), createProduct);

export default router;
