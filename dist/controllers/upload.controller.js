"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteImage = exports.uploadAvatar = exports.uploadImage = void 0;
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const uploadImage = async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: 'No image file provided'
            });
        }
        const file = req.file;
        const protocol = req.protocol;
        const host = req.get('host');
        const imageUrl = `${protocol}://${host}/uploads/${file.filename}`;
        console.log(`✅ Image uploaded successfully: ${file.filename}`);
        return res.status(200).json({
            success: true,
            message: 'Image uploaded successfully',
            url: imageUrl,
            imageUrl: imageUrl,
            filename: file.filename,
            size: file.size,
            mimetype: file.mimetype
        });
    }
    catch (error) {
        console.error('Upload image error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to upload image',
            error: error instanceof Error ? error.message : 'Unknown error'
        });
    }
};
exports.uploadImage = uploadImage;
const uploadAvatar = async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: 'No avatar file provided'
            });
        }
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({
                success: false,
                message: 'Unauthorized'
            });
        }
        const file = req.file;
        const protocol = req.protocol;
        const host = req.get('host');
        const avatarUrl = `${protocol}://${host}/uploads/${file.filename}`;
        const updatedUser = await prisma_1.default.user.update({
            where: { id: userId },
            data: { avatarUrl }
        });
        console.log(`✅ Avatar uploaded successfully for user ${userId}: ${file.filename}`);
        return res.status(200).json({
            success: true,
            message: 'Avatar uploaded successfully',
            avatarUrl,
            user: updatedUser
        });
    }
    catch (error) {
        console.error('Upload avatar error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to upload avatar',
            error: error instanceof Error ? error.message : 'Unknown error'
        });
    }
};
exports.uploadAvatar = uploadAvatar;
const deleteImage = async (req, res) => {
    try {
        const { filename } = req.params;
        if (!filename) {
            return res.status(400).json({
                success: false,
                message: 'Filename is required'
            });
        }
        const uploadsDir = path_1.default.join(__dirname, '../../uploads');
        const filenameStr = (0, http_1.firstStr)(req.params.filename);
        if (!filenameStr)
            return res.status(400).json({ success: false, message: 'Filename is required' });
        const filePath = path_1.default.join(uploadsDir, filenameStr);
        if (!fs_1.default.existsSync(filePath)) {
            return res.status(404).json({
                success: false,
                message: 'Image not found'
            });
        }
        fs_1.default.unlinkSync(filePath);
        console.log(`🗑️ Image deleted successfully: ${filename}`);
        return res.status(200).json({
            success: true,
            message: 'Image deleted successfully'
        });
    }
    catch (error) {
        console.error('Delete image error:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to delete image',
            error: error instanceof Error ? error.message : 'Unknown error'
        });
    }
};
exports.deleteImage = deleteImage;
//# sourceMappingURL=upload.controller.js.map