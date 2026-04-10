import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import prisma from '../utils/prisma';
import { getPublicBaseUrl } from '../utils/public-url';
import { firstStr } from '../utils/http';
/**
 * Upload a general image (for rooms, gifts, etc.)
 * Returns the image URL that can be used in the application
 */
export const uploadImage = async (req: Request, res: Response) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No image file provided'
      });
    }

    const file = req.file;
    const baseUrl = getPublicBaseUrl(req);
    const imageUrl = `${baseUrl}/uploads/${file.filename}`;

    console.log(`✅ Image uploaded successfully: ${file.filename}`);

    return res.status(200).json({
      success: true,
      message: 'Image uploaded successfully',
      url: imageUrl,              // Primary field
      imageUrl: imageUrl,         // Backward compatibility
      filename: file.filename,
      size: file.size,
      mimetype: file.mimetype
    });

  } catch (error) {
    console.error('Upload image error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to upload image',
      error: error instanceof Error ? error.message : 'Unknown error'
    });
  }
};

/**
 * Upload a user avatar and update the user's profile
 * This endpoint updates the user's avatarUrl in the database
 * The avatar will appear in room screens where the user is displayed
 */
export const uploadAvatar = async (req: Request, res: Response) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No avatar file provided'
      });
    }

    const userId = (req as any).userId;
if (!userId) {
  return res.status(401).json({
    success: false,
    message: 'Unauthorized'
  });
}


    const file = req.file;
    const baseUrl = getPublicBaseUrl(req);
    const avatarUrl = `${baseUrl}/uploads/${file.filename}`;

    // Update user's avatar URL in database
    const updatedUser = await prisma.user.update({
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

  } catch (error) {
    console.error('Upload avatar error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to upload avatar',
      error: error instanceof Error ? error.message : 'Unknown error'
    });
  }
};

/**
 * Delete an image from the uploads directory
 * This can be used to clean up old images when they are replaced
 */
export const deleteImage = async (req: Request, res: Response) => {
  try {
    const { filename } = req.params;

    if (!filename) {
      return res.status(400).json({
        success: false,
        message: 'Filename is required'
      });
    }

    const uploadsDir = path.join(__dirname, '../../uploads');
const filenameStr = firstStr(req.params.filename);
if (!filenameStr) return res.status(400).json({ success:false, message:'Filename is required' });

const filePath = path.join(uploadsDir, filenameStr);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
        success: false,
        message: 'Image not found'
      });
    }

    fs.unlinkSync(filePath);
    console.log(`🗑️ Image deleted successfully: ${filename}`);

    return res.status(200).json({
      success: true,
      message: 'Image deleted successfully'
    });

  } catch (error) {
    console.error('Delete image error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to delete image',
      error: error instanceof Error ? error.message : 'Unknown error'
    });
  }
};