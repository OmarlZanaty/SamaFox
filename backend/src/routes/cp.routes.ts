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
} from '../services/cp.service';

/**
 * A15 / #20 / #44 — نظام الـ CP.
 *   POST   /cp/requests            send a CP gift invitation (charges nothing yet)
 *   GET    /cp/requests/pending    invitations waiting on me
 *   POST   /cp/requests/:id/accept full price charged, pair created
 *   POST   /cp/requests/:id/reject no gift, 30% of the price charged
 *   DELETE /cp/requests/:id        sender withdraws his own invitation
 *   GET    /cp/partners            "الاشخاص اللي عامل معاهم CP" (+ :userId for a profile)
 *   DELETE /cp/partners/:userId    "الغاء CP مع فلان؟"
 */
const router = Router();

const fail = (res: any, err: unknown) => {
  if (err instanceof CpError) {
    return res.status(err.status).json({ success: false, code: err.code, message: err.message });
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
