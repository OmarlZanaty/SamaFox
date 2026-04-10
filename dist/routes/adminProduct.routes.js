"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const adminProduct_controller_1 = require("../controllers/adminProduct.controller");
const router = (0, express_1.Router)();
const storage = multer_1.default.diskStorage({
    destination: (req, file, cb) => {
        cb(null, "uploads/");
    },
    filename: (req, file, cb) => {
        const unique = Date.now() + "-" + file.originalname;
        cb(null, unique);
    },
});
const upload = (0, multer_1.default)({ storage });
router.post("/products", upload.single("file"), (req, res, next) => {
    console.log("🔥 MULTER HIT");
    next();
}, adminProduct_controller_1.createProduct);
exports.default = router;
//# sourceMappingURL=adminProduct.routes.js.map