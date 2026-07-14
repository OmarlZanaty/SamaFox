// File: samafox-backend/src/routes/room-admin.routes.ts
// Room Admin Routes

import { Router } from 'express';
import * as roomAdminController from '../controllers/room-admin.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// Admin management
router.post('/add-admin', roomAdminController.addRoomAdmin);
router.post('/remove-admin', roomAdminController.removeRoomAdmin);
router.get('/:roomId/admins', roomAdminController.getRoomAdmins);

// User moderation
router.post('/mute', roomAdminController.muteUser);
router.post('/ban', roomAdminController.banUser);
router.post('/unban', roomAdminController.unbanUser);
router.post('/seat-block', roomAdminController.setSeatBlock);
router.post('/kick', roomAdminController.kickUser);
router.get('/:roomId/bans', roomAdminController.getBanList);
router.get('/:roomId/moderated', roomAdminController.getModeratedUsers);

// Room settings
router.post('/lock', roomAdminController.toggleRoomLock);
router.post('/max-seats', roomAdminController.updateMaxSeats);
router.post('/background-music', roomAdminController.setBackgroundMusic);
router.post('/background-image', roomAdminController.updateRoomBackground);
router.post('/sound-settings', roomAdminController.toggleSoundSettings);

// Chat management
router.post('/clear-chat', roomAdminController.clearChat);

// #4: reset per-user room coin counters
router.post('/reset-earnings', roomAdminController.resetSeatEarnings);

export default router;
