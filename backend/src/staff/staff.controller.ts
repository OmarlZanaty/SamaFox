import { RequestHandler } from 'express';
import { requestIp } from '../services/adminAudit.service';
import { Operation, runStaffAction, StaffError } from './staff.service';

export const staffResponses: RequestHandler = (_req, res, next) => {
  // Shared authentication predates the Arabic staff contract. Localize its
  // error envelope here without changing other applications' auth responses.
  const json = res.json.bind(res);
  res.json = body => {
    if (body?.success === false && typeof body.message === 'string' && !/[\u0600-\u06ff]/.test(body.message)) {
      body = { ...body, message: res.statusCode === 401 ? 'يرجى تسجيل الدخول مجدداً' :
        res.statusCode === 403 ? 'ليس لديك الصلاحية المطلوبة' : 'تعذر تنفيذ العملية، يرجى المحاولة لاحقاً' };
    }
    return json(body);
  };
  res.set('Cache-Control', 'no-store');
  next();
};

export function staffController(operation: Operation, dashboard = false): RequestHandler {
  return async (req, res) => {
    try {
      const data = await runStaffAction({ userId: req.userId!, dashboard, ip: requestIp(req),
        userAgent: [req.get('x-device-id'), req.get('user-agent')].filter(Boolean).join(' | '),
        reason: typeof req.body?.reason === 'string' ? req.body.reason : null }, operation,
      operation === 'appoint' && dashboard ? { ...req.body, role: 'MANAGER' } : req.body ?? {}, req.params, req.query);
      return res.json({ success: true, data });
    } catch (error) {
      if (error instanceof StaffError) return res.status(error.status).json({ success: false, message: error.message });
      console.error('[staff] request failed', error);
      return res.status(500).json({ success: false, message: 'تعذر تنفيذ العملية، يرجى المحاولة لاحقاً' });
    }
  };
}
