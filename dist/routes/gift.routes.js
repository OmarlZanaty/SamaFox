"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const gift_controller_1 = require("../controllers/gift.controller");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const giftLimiter_1 = require("../middlewares/giftLimiter");
const router = (0, express_1.Router)();
router.get('/', gift_controller_1.getGifts);
router.post('/send', auth_middleware_1.authMiddleware, gift_controller_1.sendGift);
router.get('/history', auth_middleware_1.authMiddleware, gift_controller_1.getGiftHistory);
router.post("/sendGift", giftLimiter_1.giftLimiter, gift_controller_1.sendGift);
exports.default = router;
//# sourceMappingURL=gift.routes.js.map