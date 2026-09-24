import { Request, Response } from 'express';
import { optimizeUpload, GIF_POLICY, GifRole } from '../utils/mediaOptimize';
import path from 'path';
import fs from 'fs';
import fsp from 'fs/promises';
import prisma from '../utils/prisma';
import { probeGiftVideo, needsTranscode, transcodeToH264 } from '../gifts/videoValidate';
import { getPublicBaseUrl } from '../utils/public-url';
import { firstStr } from '../utils/http';
import { canUseAnimatedAvatar, isAnimatedImage } from '../services/animatedAvatar.service';
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

    // C10 — the animated-image perk was enforced on the AVATAR endpoint only.
    // This one takes the room picture, so the gate was trivially sidestepped:
    // upload the GIF here and point the room at it. Same tier config, checked
    // at the only other place an image file enters the system.
    //
    // Admins are exempt on purpose — this endpoint is also what the dashboard
    // posts gift and product artwork through, and animated gift icons are the
    // whole point of the catalogue.
    const uploaderId = (req as any).userId as number | undefined;
    if (
      uploaderId &&
      isAnimatedImage({ filename: file.filename, mimetype: file.mimetype })
    ) {
      const uploader = await prisma.user.findUnique({
        where: { id: uploaderId },
        select: { isAdmin: true },
      });
      if (!uploader?.isAdmin) {
        const { allowed, minLevel } = await canUseAnimatedAvatar(uploaderId);
        if (!allowed) {
          try {
            await fsp.unlink(file.path);
          } catch {
            /* the temp file is disposable; a failed cleanup must not fail the request */
          }
          return res.status(403).json({
            success: false,
            code: 'ANIMATED_IMAGE_NOT_ALLOWED',
            message:
              minLevel == null
                ? 'الصورة المتحركة غير متاحة حالياً'
                : `الصورة المتحركة متاحة لأعضاء VIP ${minLevel} فما فوق`,
          });
        }
      }
    }

    // Shrink before anyone downloads it: chat pictures and room backgrounds
    // are capped at 1600px and re-encoded as WebP; a GIF keeps its size and
    // gets a real palette. Whatever fails leaves the original in place.
    // A GIF is also brought within the role policy (pixels + frames); the
    // dashboard passes ?gifRole= for product art, everything else is treated
    // as a background (the largest allowance). Beyond the hard ceiling the
    // file is refused with the reason instead of shipped to every phone.
    const roleParam = String(req.query.gifRole ?? '').trim() as GifRole;
    const gifRole: GifRole = (roleParam in GIF_POLICY) ? roleParam : 'bg';
    let opt;
    try {
      opt = await optimizeUpload(file.path, { resizeTo: 1600, gifRole });
    } catch (e) {
      await fsp.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, code: 'GIF_TOO_HEAVY', message: (e as Error).message });
    }
    const storedName = path.basename(opt.path);

    const baseUrl = getPublicBaseUrl(req);
    const imageUrl = `${baseUrl}/uploads/${storedName}`;

    console.log(`✅ Image uploaded: ${storedName} (${opt.before}→${opt.after} bytes)`);

    return res.status(200).json({
      success: true,
      message: 'Image uploaded successfully',
      url: imageUrl,              // Primary field
      imageUrl: imageUrl,         // Backward compatibility
      filename: storedName,
      size: opt.after,
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

    // Big or tall clips are brought to ≤720p / crf 26 — a 16 MB upload is
    // ~2 MB on the phone. Alpha clips are left alone (yuv420p has no alpha).
    if (!probe.hasAlpha && (file.size > 6 * 1024 * 1024 || probe.height > 720)) {
      const shrunk = await optimizeUpload(file.path);
      if (shrunk.changed) console.log(`✅ Gift video shrunk ${shrunk.before}→${shrunk.after} bytes`);
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
 * A video the user picked as his PROFILE-PAGE BACKGROUND.
 *
 * Deliberately not the gift path: a wallpaper clip has no 15-second or
 * resolution rules to obey. All that matters is that the phone can decode it,
 * so an iPhone's HEVC recording is converted to H.264 and everything else is
 * stored as uploaded. Size is capped by multer on the route.
 */
export const uploadBackgroundVideo = async (req: Request, res: Response) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No video file provided' });
    }
    const file = req.file;

    let codec = 'unknown';
    let transcoded = false;
    try {
      const probe = await probeGiftVideo(file.path).catch(() => null);
      codec = probe?.codec ?? 'unknown';
      if (codec !== 'unknown' && needsTranscode(codec)) {
        await transcodeToH264(file.path);
        transcoded = true;
      }
    } catch (err) {
      // A probe/convert failure must not lose the upload — the clip may still
      // play fine. Only a genuinely undecodable file will look broken, and the
      // page falls back to its gradient when it does.
      console.warn('[uploadBackgroundVideo] probe/transcode skipped:', (err as Error).message);
    }

    const baseUrl = getPublicBaseUrl(req);
    const url = `${baseUrl}/uploads/${file.filename}`;
    return res.status(200).json({
      success: true,
      message: 'Video uploaded successfully',
      url,
      filename: file.filename,
      mimetype: file.mimetype,
      codec: transcoded ? 'h264' : codec,
      transcoded,
    });
  } catch (error) {
    console.error('Upload background video error:', error);
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

    // A16 - an animated avatar is a VIP perk configured per tier in the
    // dashboard. Checked here, at the only place an avatar file enters the
    // system, so a client that skips the UI gate still cannot use one.
    if (isAnimatedImage({ filename: file.filename, mimetype: file.mimetype })) {
      const { allowed, minLevel } = await canUseAnimatedAvatar(userId);
      if (!allowed) {
        try {
          await fsp.unlink(file.path);
        } catch {
          /* the temp file is disposable; a failed cleanup must not fail the request */
        }
        return res.status(403).json({
          success: false,
          code: 'ANIMATED_AVATAR_NOT_ALLOWED',
          message:
            minLevel == null
              ? 'الصورة المتحركة غير متاحة حالياً'
              : `الصورة المتحركة متاحة لأعضاء VIP ${minLevel} فما فوق`,
        });
      }
    }

    const baseUrl = getPublicBaseUrl(req);
    // An avatar is never shown above 512px; a 4 MB photo is 40 KB after this.
    let optAvatar;
    try {
      optAvatar = await optimizeUpload(file.path, { resizeTo: 512, gifMaxSide: 512, gifRole: 'frame' });
    } catch (e) {
      await fsp.unlink(file.path).catch(() => {});
      return res.status(400).json({ success: false, code: 'GIF_TOO_HEAVY', message: (e as Error).message });
    }
    const avatarUrl = `${baseUrl}/uploads/${path.basename(optAvatar.path)}`;

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
