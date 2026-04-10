"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.giftLimiter = void 0;
const express_rate_limit_1 = __importDefault(require("express-rate-limit"));
exports.giftLimiter = (0, express_rate_limit_1.default)({
    windowMs: 5 * 1000,
    max: 15,
    message: "Too many gifts sent. Slow down."
});
//# sourceMappingURL=giftLimiter.js.map