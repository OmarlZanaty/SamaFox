import { Router } from "express";
import multer from "multer";
import { createProduct } from "../controllers/adminProduct.controller";

const router = Router();

// ✅ IMPORTANT: use diskStorage (not dest)
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, "uploads/");
  },
  filename: (req, file, cb) => {
    const unique = Date.now() + "-" + file.originalname;
    cb(null, unique);
  },
});

const upload = multer({ storage });

// ✅ VERY IMPORTANT: multer MUST be first
router.post(
  "/products",
  upload.single("file"), // 👈 MUST MATCH formData.append("file")
  (req, res, next) => {
    console.log("🔥 MULTER HIT");
    next();
  },
  createProduct
);

export default router;