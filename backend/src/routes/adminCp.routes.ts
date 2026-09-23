import { Router } from 'express';
import multer from 'multer';
import { requestIp } from '../services/adminAudit.service';
import { CpError } from '../services/cpUnlock.service';
import {
  adminDeletePair,
  adminLockCp,
  adminSetFeatured,
  adminUnlockCp,
  adminUpdatePair,
  createBackground,
  deleteBackground,
  getCpPolicy,
  getUserCpOverview,
  grantBackground,
  grantCpUnlock,
  listAuditLog,
  listBackgrounds,
  listCpGifts,
  listCpGrants,
  listUserBackgrounds,
  resolveUser,
  revokeBackground,
  revokeCpGrant,
  updateBackground,
  updateCpGift,
  updateCpPolicy,
} from '../services/cpAdmin.service';
import { buildPosterUrl, publicBaseUrl } from '../controllers/adminProduct.controller';

/**
 * لوحة تحكم CP والخلفيات (2026-09-22).
 *
 * Mounted INSIDE the dashboard router (adminDashboard.routes.ts), so every
 * request here has already passed `authenticate` + `requireAdminDashboard`
 * (isAdmin checked on the users row, server-side). Nothing in this file
 * trusts a role claim from the client.
 *
 *   /admin-dashboard/cp/policy                 GET | PATCH   system unlock mode / fee, level step
 *   /admin-dashboard/cp/grants                 GET | POST    per-user "فتح CP مجانًا" / "فتح CP برسوم"
 *   /admin-dashboard/cp/grants/:userId         DELETE        revoke
 *   /admin-dashboard/cp/users/:id              GET           one user's CP data (id = displayId or row id)
 *   /admin-dashboard/cp/users/:id/unlock       POST | DELETE open / close CP for him
 *   /admin-dashboard/cp/users/:id/featured     PATCH         "مستخدم CP الظاهر"
 *   /admin-dashboard/cp/pairs/:pairId          PATCH | DELETE cpValue / levelOverride / dissolve
 *   /admin-dashboard/cp/gifts                  GET           gifts in the cp list
 *   /admin-dashboard/cp/gifts/:id              PATCH         price / active / order
 *   /admin-dashboard/cp/audit                  GET           سجل العمليات
 *   /admin-dashboard/backgrounds               GET | POST    catalogue (POST = multipart file)
 *   /admin-dashboard/backgrounds/:id           PATCH | DELETE
 *   /admin-dashboard/backgrounds/:id/grant     POST          { userId | displayId }
 *   /admin-dashboard/backgrounds/:id/revoke    POST          { userId | displayId, reason? }
 *   /admin-dashboard/backgrounds/users/:id     GET           what one user owns
 */

const ctxOf = (req: any) => ({ adminId: Number(req.userId ?? req.authUser?.id) || 0, ip: requestIp(req) });

const fail = (res: any, err: unknown) => {
  if (err instanceof CpError) {
    return res.status(err.status).json({ success: false, code: err.code, message: err.message, ...(err.data ?? {}) });
  }
  const anyErr = err as { code?: string; status?: number; message?: string };
  if (anyErr?.code === 'P2025') return res.status(404).json({ success: false, message: 'غير موجود' });
  console.error('[admin-cp]', err);
  return res.status(500).json({ success: false, message: 'حدث خطأ غير متوقع' });
};

/** `:id` in these routes is whatever the admin typed: displayId first, row id second. */
async function userFromParam(req: any) {
  const by = String(req.query?.by ?? '') === 'id' ? 'id' : 'auto';
  return resolveUser(req.params.id ?? req.params.userId, by);
}

async function userFromBody(body: any) {
  if (body?.userId != null && body.userId !== '') return resolveUser(body.userId, 'id');
  return resolveUser(body?.displayId ?? body?.id, 'auto');
}

// ============================================================
// CP
// ============================================================
export const adminCpRouter = Router();

adminCpRouter.get('/policy', async (_req, res) => {
  try {
    return res.json({ success: true, data: await getCpPolicy() });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.patch('/policy', async (req, res) => {
  try {
    const b = req.body ?? {};
    return res.json({
      success: true,
      data: await updateCpPolicy(
        {
          unlockMode: b.unlockMode,
          unlockFeeCoins: b.unlockFeeCoins,
          levelStepCoins: b.levelStepCoins,
          levelMax: b.levelMax,
          levelNames: b.levelNames,
        },
        ctxOf(req),
      ),
    });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.get('/grants', async (req, res) => {
  try {
    const userId = req.query.userId ? Number(req.query.userId) : undefined;
    return res.json({ success: true, data: await listCpGrants(undefined, { userId, limit: Number(req.query.limit) || 200 }) });
  } catch (e) {
    return fail(res, e);
  }
});

// body: { displayId | userId, mode: FREE | FEE, feeCoins?, note? }
adminCpRouter.post('/grants', async (req, res) => {
  try {
    const user = await userFromBody(req.body);
    const mode = String(req.body?.mode ?? 'FREE').toUpperCase() as 'FREE' | 'FEE';
    if (mode !== 'FREE' && mode !== 'FEE') return res.status(400).json({ success: false, message: 'mode يجب أن يكون FREE أو FEE' });
    const grant = await grantCpUnlock(user.id, { mode, feeCoins: req.body?.feeCoins, note: req.body?.note }, ctxOf(req));
    return res.json({ success: true, data: { user, grant } });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.delete('/grants/:userId', async (req, res) => {
  try {
    const user = await userFromParam(req);
    return res.json({ success: true, data: { user, ...(await revokeCpGrant(user.id, ctxOf(req))) } });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.get('/users/:id', async (req, res) => {
  try {
    const user = await userFromParam(req);
    return res.json({ success: true, data: await getUserCpOverview(user.id) });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.post('/users/:id/unlock', async (req, res) => {
  try {
    const user = await userFromParam(req);
    return res.json({ success: true, data: { user, ...(await adminUnlockCp(user.id, ctxOf(req))) } });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.delete('/users/:id/unlock', async (req, res) => {
  try {
    const user = await userFromParam(req);
    return res.json({ success: true, data: { user, ...(await adminLockCp(user.id, ctxOf(req))) } });
  } catch (e) {
    return fail(res, e);
  }
});

// body: { partnerId: number | null }  (partnerId = the partner's ROW id, as listed by GET /users/:id)
adminCpRouter.patch('/users/:id/featured', async (req, res) => {
  try {
    const user = await userFromParam(req);
    const raw = req.body?.partnerId;
    const partnerId = raw == null || raw === '' ? null : Number(raw);
    if (partnerId != null && (!Number.isFinite(partnerId) || partnerId <= 0)) {
      return res.status(400).json({ success: false, message: 'partnerId غير صالح' });
    }
    return res.json({ success: true, data: await adminSetFeatured(user.id, partnerId, ctxOf(req)) });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.patch('/pairs/:pairId', async (req, res) => {
  try {
    const pairId = Number(req.params.pairId);
    if (!Number.isFinite(pairId) || pairId <= 0) return res.status(400).json({ success: false, message: 'pairId غير صالح' });
    const b = req.body ?? {};
    const patch: any = {};
    if (b.cpValue !== undefined) patch.cpValue = b.cpValue;
    if (b.levelOverride !== undefined) patch.levelOverride = b.levelOverride === '' ? null : b.levelOverride;
    return res.json({ success: true, data: await adminUpdatePair(pairId, patch, ctxOf(req)) });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.delete('/pairs/:pairId', async (req, res) => {
  try {
    const pairId = Number(req.params.pairId);
    if (!Number.isFinite(pairId) || pairId <= 0) return res.status(400).json({ success: false, message: 'pairId غير صالح' });
    return res.json({ success: true, data: await adminDeletePair(pairId, ctxOf(req)) });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.get('/gifts', async (_req, res) => {
  try {
    return res.json({ success: true, data: await listCpGifts() });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.patch('/gifts/:id', async (req, res) => {
  try {
    const b = req.body ?? {};
    return res.json({
      success: true,
      data: await updateCpGift(String(req.params.id), { coinCost: b.coinCost, isActive: b.isActive, sortOrder: b.sortOrder, nameAr: b.nameAr }, ctxOf(req)),
    });
  } catch (e) {
    return fail(res, e);
  }
});

adminCpRouter.get('/audit', async (req, res) => {
  try {
    const q: any = req.query ?? {};
    let userId: number | undefined;
    if (q.userId) {
      const u = await resolveUser(q.userId, 'auto');
      userId = u.id;
    }
    return res.json({
      success: true,
      data: await listAuditLog({
        userId,
        action: q.action ? String(q.action) : undefined,
        limit: Number(q.limit) || 100,
        before: Number(q.before) || undefined,
      }),
    });
  } catch (e) {
    return fail(res, e);
  }
});

// ============================================================
// Backgrounds
// ============================================================
export const adminBackgroundsRouter = Router();

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, 'uploads/'),
    filename: (_req, file, cb) => {
      // Same rule as adminProduct.routes: extension from the MIME type, never
      // from the client's file name.
      const mimeToExt: Record<string, string> = {
        'image/jpeg': '.jpg',
        'image/png': '.png',
        'image/webp': '.webp',
        'image/gif': '.gif',
        'video/mp4': '.mp4',
        'video/webm': '.webm',
      };
      cb(null, `${Date.now()}-bg${mimeToExt[file.mimetype] ?? '.bin'}`);
    },
  }),
  limits: { fileSize: 60 * 1024 * 1024 },
});

adminBackgroundsRouter.get('/', async (_req, res) => {
  try {
    return res.json({ success: true, data: await listBackgrounds() });
  } catch (e) {
    return fail(res, e);
  }
});

// multipart: file + name + price_coins + is_free + is_private + duration_days
adminBackgroundsRouter.post('/', upload.single('file'), async (req: any, res) => {
  try {
    const file = req.file;
    if (!file) return res.status(400).json({ success: false, message: 'يجب رفع صورة أو فيديو' });
    const isVideo = String(file.mimetype).startsWith('video/');
    if (!isVideo && !String(file.mimetype).startsWith('image/')) {
      return res.status(400).json({ success: false, message: 'يجب رفع صورة أو فيديو' });
    }
    const baseUrl = publicBaseUrl(req);
    const assetUrl = `${baseUrl}/uploads/${file.filename}`;
    const previewUrl = await buildPosterUrl(file, isVideo, baseUrl);
    const b = req.body ?? {};
    const truthy = (v: unknown) => v === true || v === 'true' || v === '1' || v === 1;
    const rawDays = b.duration_days ?? b.durationDays;
    const days = rawDays == null || String(rawDays).trim() === '' ? null : Math.floor(Number(rawDays));
    const bg = await createBackground(
      {
        name: b.name,
        assetUrl,
        previewUrl,
        priceCoins: Number(b.price_coins ?? b.priceCoins ?? 0),
        isFree: truthy(b.is_free ?? b.isFree),
        isPurchasable: !truthy(b.is_private ?? b.isPrivate),
        durationDays: days && days > 0 ? days : null,
      },
      ctxOf(req),
    );
    return res.json({ success: true, data: bg });
  } catch (e) {
    return fail(res, e);
  }
});

adminBackgroundsRouter.patch('/:id', async (req, res) => {
  try {
    const b = req.body ?? {};
    const patch: any = {};
    if (b.name !== undefined) patch.name = b.name;
    if (b.priceCoins !== undefined || b.price_coins !== undefined) patch.priceCoins = b.priceCoins ?? b.price_coins;
    if (b.isFree !== undefined || b.is_free !== undefined) patch.isFree = (b.isFree ?? b.is_free) === true || (b.isFree ?? b.is_free) === 'true';
    if (b.isPurchasable !== undefined) patch.isPurchasable = b.isPurchasable === true || b.isPurchasable === 'true';
    if (b.isPrivate !== undefined || b.is_private !== undefined) patch.isPurchasable = !((b.isPrivate ?? b.is_private) === true || (b.isPrivate ?? b.is_private) === 'true');
    if (b.durationDays !== undefined || b.duration_days !== undefined) patch.durationDays = b.durationDays ?? b.duration_days;
    return res.json({ success: true, data: await updateBackground(String(req.params.id), patch, ctxOf(req)) });
  } catch (e) {
    return fail(res, e);
  }
});

adminBackgroundsRouter.delete('/:id', async (req, res) => {
  try {
    return res.json({ success: true, data: await deleteBackground(String(req.params.id), ctxOf(req)) });
  } catch (e) {
    return fail(res, e);
  }
});

adminBackgroundsRouter.post('/:id/grant', async (req, res) => {
  try {
    const user = await userFromBody(req.body);
    const row = await grantBackground(String(req.params.id), user.id, ctxOf(req));
    return res.json({ success: true, data: { user, userItem: row } });
  } catch (e) {
    return fail(res, e);
  }
});

adminBackgroundsRouter.post('/:id/revoke', async (req, res) => {
  try {
    const user = await userFromBody(req.body);
    const out = await revokeBackground(String(req.params.id), user.id, ctxOf(req), undefined, req.body?.reason);
    return res.json({ success: true, data: { user, ...out } });
  } catch (e) {
    return fail(res, e);
  }
});

adminBackgroundsRouter.get('/users/:id', async (req, res) => {
  try {
    const user = await userFromParam(req);
    return res.json({ success: true, data: await listUserBackgrounds(user.id) });
  } catch (e) {
    return fail(res, e);
  }
});
