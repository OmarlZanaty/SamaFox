import { Router } from "express";
import multer from "multer";
import prisma from "../utils/prisma";
import { createProduct, deleteProduct, listProductsAdmin, setProductVisibility, grantProduct } from "../controllers/adminProduct.controller"; // ✅ FIX: import cascade-safe deleteProduct
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
    // ✅ FIX: force extension from MIME type — never trust original extension
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/webp': '.webp',
      'image/gif': '.gif',
      'video/mp4': '.mp4',
      'video/webm': '.webm',
    };
    const ext = mimeToExt[file.mimetype] ?? '.bin';
    cb(null, `${Date.now()}${ext}`);
  },
});

const upload = multer({ storage });

router.post("/products", authMiddleware, adminMiddleware, upload.single("file"), createProduct);

// ✅ FIX: register cascade-safe delete (clears activeFrameId, removes userItems before deleting item)
router.delete("/products/:id", authMiddleware, adminMiddleware, deleteProduct);

// Group 9: dashboard list (incl. private store), visibility toggle, manual grant by ID
router.get("/products", authMiddleware, adminMiddleware, listProductsAdmin);
router.patch("/products/:id", authMiddleware, adminMiddleware, setProductVisibility);
router.post("/grant", authMiddleware, adminMiddleware, grantProduct);

export default router;