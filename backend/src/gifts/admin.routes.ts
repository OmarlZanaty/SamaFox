import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import os from 'os';
import { authMiddleware } from '../middlewares/auth.middleware';
import { adminMiddleware } from '../middlewares/admin.middleware';
import { rateLimitMw } from './rateLimit';
import * as admin from './admin.controller';

const upload = multer({
  dest: path.join(os.tmpdir(), 'gift-uploads'),
  limits: { fileSize: 16 * 1024 * 1024 },
});

const router = Router();

router.use(authMiddleware, adminMiddleware);

const adminRate = rateLimitMw('admin_write', (req) => req.userId ?? null);
const uploadRate = rateLimitMw('upload', (req) => req.userId ?? null);

router.get('/', admin.listAll);
// B4/B5/B6 — قوائم الهدايا. MUST stay above the '/:id' routes below, otherwise
// Express matches "categories" as a gift id and every list read 404s.
router.get('/categories', admin.listCategories);
router.post('/categories', adminRate, admin.createCategory);
router.patch('/categories/:id', adminRate, admin.updateCategory);
router.delete('/categories/:id', adminRate, admin.deleteCategory);
router.get('/templates', admin.listTemplates);
router.get('/templates/:key', admin.getTemplate);
router.get('/audit-log', admin.auditLog);
router.get('/export', admin.exportAll);
router.get('/:id', admin.getOne);
router.get('/:id/preview', admin.preview);

router.post('/', adminRate, admin.create);
router.patch('/:id', adminRate, admin.update);
router.delete('/:id', adminRate, admin.softDelete);
router.post('/reorder', adminRate, admin.reorder);
// B6 — "نقل إلى قائمة" on an existing gift.
router.post('/:id/move', adminRate, admin.moveGiftToCategory);
router.post('/bulk-import', adminRate, admin.bulkImport);
router.post('/upload-video', uploadRate, upload.single('file'), admin.uploadVideo);
router.post('/upload-icon', uploadRate, upload.single('file'), admin.uploadIcon);

export default router;
