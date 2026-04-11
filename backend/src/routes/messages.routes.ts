import { Router } from 'express';
import {
  getConversations,
  getOrCreateConversation,
  getMessages,
  sendMessage,
  markConversationRead,
} from '../controllers/messages.controller';
import { authenticate as requireAuth } from '../middlewares/auth.middleware';
import multer from "multer";
import path from "path";
import fs from "fs";
import { getPublicBaseUrl } from '../utils/public-url';

const router = Router();

// inbox list
router.get('/conversations', requireAuth, getConversations);

// create/get conversation with partner
router.post('/conversation', requireAuth, getOrCreateConversation);

// messages in a conversation
router.get('/conversations/:conversationId/messages', requireAuth, getMessages);

// send message
router.post('/send', requireAuth, sendMessage);

// mark read
router.post('/conversations/:conversationId/read', requireAuth, markConversationRead);


const uploadDir = path.join(process.cwd(), "uploads", "audio");
fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || ".aac");
    cb(null, `audio_${Date.now()}${ext}`);
  },
});

const upload = multer({ storage });

router.post("/upload-audio", requireAuth, upload.single("file"), async (req, res) => {
  if (!req.file) return res.status(400).json({ message: "file is required" });

  // if you already serve /uploads as static => this URL works
  const audioUrl = `${getPublicBaseUrl(req)}/uploads/audio/${req.file.filename}`;
  return res.json({ audioUrl });
});

router.post("/:id/react", async (req, res) => {
  const messageId = Number(req.params.id);
  const { emoji } = req.body;

  if (!messageId) return res.status(400).json({ message: "invalid messageId" });
  if (!emoji) return res.status(400).json({ message: "emoji is required" });

  // TODO: save in DB (MessageReaction table recommended)
  // For now just return ok to unblock Flutter UI:
  return res.json({ ok: true });
});
export default router;
