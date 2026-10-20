import { RequestHandler } from 'express';
import { rememberRoomApi } from '../services/roomSession.service';

/** Only method + route template: never queries, tokens, PINs or request bodies. */
export const rememberLastRoomApi: RequestHandler = (req, res, next) => {
  res.once('finish', () => {
    if (req.userId && req.route?.path) {
      rememberRoomApi(req.userId, `${req.method} ${req.baseUrl}${req.route.path}`);
    }
  });
  next();
};
