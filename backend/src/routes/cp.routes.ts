import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import {
  CpError,
  acceptCpRequest,
  cancelCpRequest,
  createCpRequest,
  listCpPartners,
  listPendingCpRequests,
  rejectCpRequest,
  removeCpPair,
  setFeaturedPartner,
} from '../services/cp.service';
import { confirmCpUnlock, getCpUnlockStatus } from '../services/cpUnlock.service';

/**
 * A15 / #20 / #44 — نظام الـ CP.
 *   POST   /cp/requests            send a CP gift invitation (charges nothing yet)
 *   GET    /cp/requests/pending    invitations waiting on me
 *   POST   /cp/requests/:id/accept full price charged, pair created
 *   POST   /cp/requests/:id/reject no gift, 30% of the price charged
 *   DELETE /cp/requests/:id        sender withdraws his own invitation
 *   GET    /cp/partners            "الاشخاص اللي عامل معاهم CP" (+ :userId for a profile)
 *   DELETE /cp/partners/:userId    "الغاء CP مع فلان؟"
 *
 * صلاحيات فتح CP (2026-09-22):
 *   GET    /cp/unlock/status       am I unlocked? if not, the fee — shown before confirming
 *   POST   /cp/unlock/confirm      the user confirmed: deduct the fee (if any) and open CP
 *   PATCH  /cp/featured            "مستخدم CP الظاهر" — which partner shows beside my photo
 *
 * Nothing here can change coins, ownership or CP values directly: the only
 * debit is the quoted unlock fee, taken server-side in confirmCpUnlock.
 */
const router = Router();

const fail = (res: any, err: unknown) => {
  if (err instanceof CpError) {
    // `data` carries the quoted fee / shortfall on CP_LOCKED and
    // INSUFFICIENT_COINS so the app can show the numbers without a second call.
    return res.status(err.status).json({ success: false, code: err.code, message: err.message, ...(err.data ?? {}) });
  }
  // sendGiftAtomic throws GiftSendError, which carries the same shape but is a
  // different class; forward its status instead of flattening it to a 500.
  const anyErr = err as { status?: number; code?: string; message?: string };
  if (anyErr && typeof anyErr.status === 'number' && anyErr.code) {
    return res.status(anyErr.status).json({ success: false, code: anyErr.code, message: anyErr.message });
  }
  console.error('[cp]', err);
  return res.status(500).json({ success: false, message: 'حدث خطأ غير متوقع' });
};

const requireUserId = (req: any) => Number(req.userId ?? req.authUser?.id) || 0;

router.post('/requests', authMiddleware, async (req, res) => {
  try {
    const senderId = requireUserId(req);
    if (!senderId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const { recipientId, giftId, quantity, roomId } = req.body ?? {};
    if (!giftId || typeof giftId !== 'string') {
      return res.status(400).json({ success: false, message: 'giftId is required' });
    }
    const request = await createCpRequest({
      senderId,
      recipientId: Number(recipientId),
      giftId,
      quantity: quantity != null ? Number(quantity) : 1,
      roomId: roomId != null ? Number(roomId) : null,
    });
    return res.json({ success: true, data: request });
  } catch (e) {
    return fail(res, e);
  }
});

router.get('/requests/pending', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    return res.json({ success: true, data: await listPendingCpRequests(userId) });
  } catch (e) {
    return fail(res, e);
  }
});

router.post('/requests/:id/accept', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const result = await acceptCpRequest(Number(req.params.id), userId);
    return res.json({
      success: true,
      data: { requestId: result.request.id, pairId: result.pair.id, transactionId: result.gift.transactionId },
    });
  } catch (e) {
    return fail(res, e);
  }
});

router.post('/requests/:id/reject', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const result = await rejectCpRequest(Number(req.params.id), userId);
    return res.json({ success: true, data: { requestId: result.request.id, feeCoins: result.feeCoins } });
  } catch (e) {
    return fail(res, e);
  }
});

router.delete('/requests/:id', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    await cancelCpRequest(Number(req.params.id), userId);
    return res.json({ success: true });
  } catch (e) {
    return fail(res, e);
  }
});

// ── صلاحيات فتح CP ──────────────────────────────────────────────────────
router.get('/unlock/status', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    return res.json({ success: true, data: await getCpUnlockStatus(userId) });
  } catch (e) {
    return fail(res, e);
  }
});

router.post('/unlock/confirm', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const result = await confirmCpUnlock(userId);
    return res.json({ success: true, data: result });
  } catch (e) {
    return fail(res, e);
  }
});

// "مستخدم CP الظاهر" — body { partnerId: number | null }.
router.patch('/featured', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const raw = (req.body ?? {}).partnerId;
    const partnerId = raw == null || raw === '' ? null : Number(raw);
    if (partnerId != null && (!Number.isFinite(partnerId) || partnerId <= 0)) {
      return res.status(400).json({ success: false, message: 'partnerId غير صالح' });
    }
    return res.json({ success: true, data: await setFeaturedPartner(userId, partnerId) });
  } catch (e) {
    return fail(res, e);
  }
});

// Own list, and anyone else's for their profile card.
router.get('/partners', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    return res.json({ success: true, data: await listCpPartners(userId) });
  } catch (e) {
    return fail(res, e);
  }
});

router.get('/partners/:userId', async (req, res) => {
  try {
    const target = Number(req.params.userId);
    if (!Number.isFinite(target) || target <= 0) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }
    return res.json({ success: true, data: await listCpPartners(target) });
  } catch (e) {
    return fail(res, e);
  }
});

router.delete('/partners/:userId', authMiddleware, async (req, res) => {
  try {
    const userId = requireUserId(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    await removeCpPair(userId, Number(req.params.userId));
    return res.json({ success: true });
  } catch (e) {
    return fail(res, e);
  }
});

export default router;
