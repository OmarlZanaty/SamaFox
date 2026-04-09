import rateLimit from "express-rate-limit";

export const giftLimiter = rateLimit({
  windowMs: 5 * 1000,
  max: 15,
  message: "Too many gifts sent. Slow down."
});