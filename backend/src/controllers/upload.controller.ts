import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import fsp from 'fs/promises';
import prisma from '../utils/prisma';
import { probeGiftVideo, needsTranscode, transcodeToH264 } from '../gifts/videoValidate';
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
 * Upload a gift animation clip.
 *
 * Unlike the generic image upload this PROBES the file, so the caller learns the
 * real duration (stored as the gift's `animationMs` — the 3000ms schema default
 * used to truncate anything longer) and whether the clip carries an alpha
 * channel. Anything the client cannot play is rejected here instead of silently
 * showing a still icon in the room.
 */
export const uploadVideoAsset = async (req: Request, res: Response) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No video file provided' });
    }
    const file = req.file;

    let probe;
    try {
      probe = await probeGiftVideo(file.path);
    } catch (err) {
      await fsp.unlink(file.path).catch(() => {});
      return res.status(400).json({
        success: false,
        message: err instanceof Error ? err.message : 'فشل التحقق من الفيديو',
      });
    }

    // iPhone clips arrive as HEVC, which Chrome cannot decode at all — convert
    // before the file is ever handed to a client.
    let transcoded = false;
    if (needsTranscode(probe.codec)) {
      try {
        await transcodeToH264(file.path);
        transcoded = true;
      } catch (err) {
        console.error('[uploadVideoAsset] transcode failed', err);
        await fsp.unlink(file.path).catch(() => {});
        return res.status(400).json({
          success: false,
          message: `صيغة الفيديو (${probe.codec}) غير مدعومة وتعذّر تحويلها`,
        });
      }
    }

    const baseUrl = getPublicBaseUrl(req);
    const url = `${baseUrl}/uploads/${file.filename}`;
    console.log(
      `✅ Gift video uploaded: ${file.filename} (${probe.durationMs}ms, codec=${probe.codec}` +
        `${transcoded ? '→h264' : ''}, alpha=${probe.hasAlpha})`,
    );

    return res.status(200).json({
      success: true,
      message: 'Video uploaded successfully',
      url,
      imageUrl: url, // backward compatibility
      filename: file.filename,
      size: probe.fileSize,
      mimetype: file.mimetype,
      durationMs: probe.durationMs,
      hasAlpha: probe.hasAlpha,
      codec: transcoded ? 'h264' : probe.codec,
      transcoded,
      resolution: `${probe.width}x${probe.height}`,
      framerate: probe.framerate,
    });
  } catch (error) {
    console.error('Upload video error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to upload video',
      error: error instanceof Error ? error.message : 'Unknown error',
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

const normalizedName = path.basename(filenameStr);
if (normalizedName !== filenameStr || filenameStr.includes('..')) {
  return res.status(400).json({ success: false, message: 'Invalid filename' });
}

const filePath = path.join(uploadsDir, normalizedName);
const normalizedPath = path.normalize(filePath);
if (!normalizedPath.startsWith(path.normalize(uploadsDir + path.sep))) {
  return res.status(400).json({ success: false, message: 'Invalid filename path' });
}
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
