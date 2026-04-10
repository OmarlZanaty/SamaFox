"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const messages_controller_1 = require("../controllers/messages.controller");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const multer_1 = __importDefault(require("multer"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const router = (0, express_1.Router)();
router.get('/conversations', auth_middleware_1.authenticate, messages_controller_1.getConversations);
router.post('/conversation', auth_middleware_1.authenticate, messages_controller_1.getOrCreateConversation);
router.get('/conversations/:conversationId/messages', auth_middleware_1.authenticate, messages_controller_1.getMessages);
router.post('/send', auth_middleware_1.authenticate, messages_controller_1.sendMessage);
router.post('/conversations/:conversationId/read', auth_middleware_1.authenticate, messages_controller_1.markConversationRead);
const uploadDir = path_1.default.join(process.cwd(), "uploads", "audio");
fs_1.default.mkdirSync(uploadDir, { recursive: true });
const storage = multer_1.default.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadDir),
    filename: (_req, file, cb) => {
        const ext = path_1.default.extname(file.originalname || ".aac");
        cb(null, `audio_${Date.now()}${ext}`);
    },
});
const upload = (0, multer_1.default)({ storage });
router.post("/upload-audio", upload.single("file"), async (req, res) => {
    if (!req.file)
        return res.status(400).json({ message: "file is required" });
    const audioUrl = `${req.protocol}://${req.get("host")}/uploads/audio/${req.file.filename}`;
    return res.json({ audioUrl });
});
router.post("/:id/react", async (req, res) => {
    const messageId = Number(req.params.id);
    const { emoji } = req.body;
    if (!messageId)
        return res.status(400).json({ message: "invalid messageId" });
    if (!emoji)
        return res.status(400).json({ message: "emoji is required" });
    return res.json({ ok: true });
});
exports.default = router;
//# sourceMappingURL=messages.routes.js.map