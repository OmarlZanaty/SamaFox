import dotenv from 'dotenv';
dotenv.config();

// Last-resort handlers so a single unhandled async error in a socket/route
// handler doesn't take down the whole Node process.
process.on('unhandledRejection', (reason) => {
  console.error('[process.unhandledRejection]', reason);
});
process.on('uncaughtException', (err) => {
  console.error('[process.uncaughtException]', err);
});

import express, { Application } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { Server } from 'socket.io';
import passport from './config/passport';
import path from 'path';
import fs from 'fs';
import cookieParser from 'cookie-parser';

import chargingAgencyRoutes from './routes/charging-agency.routes';
import adminRoutes from './routes/admin.routes';
import authRoutes from './routes/auth.routes';
import userRoutes from './routes/user.routes';
import roomRoutes from './routes/room.routes';
import messageRoutes from './routes/messages.routes';
import uploadRoutes from './routes/upload.routes';
import gameRoutes from './routes/game.routes';
import roomAdminRoutes from './routes/room-admin.routes';
import adminDashboardRoutes from './routes/adminDashboard.routes';
import adminDashAuthRoutes from './routes/admin-dashboard-auth.routes';
import storeRoutes from "./routes/store.routes";
import { initializeSocketHandlers } from './services/socket.service';
import { startSkillDiceEngine } from './services/skillDice.service';
import { startSkillWheelEngine } from './services/skillWheel.service';
import { startCrashEngine } from './services/crash.service';
import { startCrazyWheelEngine } from './services/crazyWheel.service';
import { startBoxingEngine } from './services/boxing.service';
import adminProductRoutes from "./routes/adminProduct.routes";
import agencyRoutes from './agencies/agency.routes';
import searchRoutes from './search/search.routes';
import { resolvePublicDir } from './utils/publicDir';
import followRoutes from './follow/follow.routes';
import relationRoutes from './relations/relation.routes';
import notificationRoutes from './routes/notification.routes';
import vipRoutes from './routes/vip.routes';
import levelRoutes from './routes/level.routes';
import giftRoutes from './gifts/routes';
import giftAdminRoutes from './gifts/admin.routes';
import { setGiftIo } from './gifts/controller';

import helmet from 'helmet';

const app: Application = express();

// Server is served over plain HTTP (IP:3000). Helmet's default CSP adds
// `upgrade-insecure-requests` and it also sends HSTS — both force the browser
// to fetch style.css/app.js over HTTPS, which fails (no TLS) and leaves the
// admin dashboard unstyled. Disable those two; keep the rest of Helmet.
app.use(helmet({ contentSecurityPolicy: false, hsts: false }));

// Clients hit this box directly on IP:3000 — there is no nginx/ALB in front.
// `trust proxy: true` therefore trusted an X-Forwarded-For header that only an
// attacker could set, letting anyone forge req.ip and walk around the per-IP
// auth rate limiter (express-rate-limit flags this as
// ERR_ERL_PERMISSIVE_TRUST_PROXY). Set TRUST_PROXY_HOPS when a real proxy is
// added later — e.g. 1 behind a single ALB.
const trustProxyHops = Number(process.env.TRUST_PROXY_HOPS ?? 0);
app.set('trust proxy', Number.isFinite(trustProxyHops) && trustProxyHops > 0 ? trustProxyHops : false);

const normalizeOrigin = (origin: string) => origin.trim().replace(/\/+$/, '').toLowerCase();

const allowedOrigins = (process.env.CORS_ORIGIN ?? process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => normalizeOrigin(origin))
  .filter(Boolean);

const allowLocalhostInProduction = ['1', 'true', 'yes', 'on'].includes(
  String(process.env.CORS_ALLOW_LOCALHOST ?? '').toLowerCase()
);

const isLocalDevelopmentOrigin = (origin: string) => {
  try {
    const { hostname } = new URL(origin);
    return hostname === 'localhost' || hostname === '127.0.0.1';
  } catch {
    return false;
  }
};

const isOriginAllowed = (origin?: string) => {
  if (!origin) return true; // non-browser clients / same-origin calls
  const normalizedOrigin = normalizeOrigin(origin);
  if (isLocalDevelopmentOrigin(normalizedOrigin)) {
    return process.env.NODE_ENV !== 'production' || allowLocalhostInProduction;
  }
  if (allowedOrigins.length === 0) {
    // Keep production locked down, but allow local web testing when env is not production.
    return process.env.NODE_ENV !== 'production' && isLocalDevelopmentOrigin(normalizedOrigin);
  }
  if (allowedOrigins.includes('*') || allowedOrigins.includes(normalizedOrigin)) return true;

  try {
    const originHost = new URL(normalizedOrigin).host;
    return allowedOrigins.some((allowed) => {
      if (!allowed) return false;
      if (allowed.includes('://')) return new URL(allowed).host === originHost;
      return allowed === originHost || allowed === originHost.split(':')[0];
    });
  } catch {
    return allowedOrigins.includes(normalizedOrigin);
  }
};

// ✅ CORS FIRST (and allow credentials for cookies)
app.use(cors({
  origin: (origin, callback) => {
    if (isOriginAllowed(origin)) return callback(null, true);
    return callback(null, false);
  },
  credentials: true,
}));


// ✅ body + cookie parsers BEFORE routes
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

app.use('/api/v1/admin', adminRoutes);
app.use("/api/v1/store", storeRoutes);
app.use("/api/v1/admin-products", adminProductRoutes);

// passport (if you still use it elsewhere)
app.use(passport.initialize());

const publicDir = resolvePublicDir();

console.log(`📁 Serving static public directory from: ${publicDir}`);

// Always serve the admin dashboard HTML fresh (never cached) so edits to the
// dashboard show on a normal reload, before the static middleware can cache it.
app.get(['/admin-dashboard.html', '/public/admin-dashboard.html'], (_req, res) => {
  const dashboardFilePath = path.join(publicDir, 'admin-dashboard.html');
  if (!fs.existsSync(dashboardFilePath)) {
    return res.status(404).send('admin-dashboard.html not found');
  }
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  return res.sendFile(dashboardFilePath);
});

// ✅ static
app.use('/public', express.static(publicDir));
app.use(express.static(publicDir));
app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));

app.get('/public/admin-dashboard.html', (_req, res) => {
  const dashboardFilePath = path.join(publicDir, 'admin-dashboard.html');
  if (!fs.existsSync(dashboardFilePath)) {
    return res.status(404).send('admin-dashboard.html not found');
  }
  return res.sendFile(dashboardFilePath);
});

// ✅ dashboard auth first (sets cookie)
app.use('/api/v1/admin-dashboard-auth', adminDashAuthRoutes);
app.use('/admin-dashboard-auth', adminDashAuthRoutes); // backward-compatible path

// ✅ admin dashboard routes (reads cookie)
app.use('/api/v1/admin-dashboard', adminDashboardRoutes);
app.use('/admin-dashboard', adminDashboardRoutes); // backward-compatible path

// other routes
app.use('/api/v1/games', gameRoutes);
app.use('/api/v1/charging-agencies', chargingAgencyRoutes);
app.use('/api/v1/agencies', agencyRoutes);
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/rooms', roomRoutes);
app.use('/api/v1/gifts', giftRoutes);
app.use('/api/v1/admin/gifts', giftAdminRoutes);
app.use('/api/v1/messages', messageRoutes);
app.use('/api/v1/search', searchRoutes);
app.use('/api/v1/follow', followRoutes);
app.use('/api/v1/relations', relationRoutes);
app.use('/api/v1/notifications', notificationRoutes);
app.use('/api/v1/vip', vipRoutes);
app.use('/api/v1/levels', levelRoutes); // public LV catalog, mirrors /vip/levels
app.get('/api/v1/settings', require('./controllers/settings.controller').getSettings); // public CP/target config read

app.use('/api/v1/upload', uploadRoutes);
app.use('/upload', uploadRoutes); // backward-compatible path
app.use('/api/v1/room-admin', roomAdminRoutes);
app.use('/api/messages', messageRoutes); // ✅ same router

const giftAssetsDir =
  process.env.GIFT_ASSETS_DIR?.trim() || path.join(process.cwd(), 'public', 'assets');
app.use('/assets', express.static(giftAssetsDir, {
  maxAge: '30d',
  setHeaders: (res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
  },
}));
app.use('/gifts-admin', express.static(path.join(publicDir, 'gifts-admin'), {
  maxAge: '1h',
}));

// health
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', message: 'SamaFox API is running' });
});

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: (origin, callback) => {
      if (isOriginAllowed(origin)) return callback(null, true);
      return callback(null, false);
    },
    methods: ['GET', 'POST'],
    credentials: true,
  }
});

initializeSocketHandlers(io);
setGiftIo(io);
startSkillDiceEngine(io);
startSkillWheelEngine(io);
startCrashEngine(io);
startCrazyWheelEngine(io);
startBoxingEngine(io);

// error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err.stack);
  const status = err.status || 500;
  const isServerError = status >= 500;
  res.status(err.status || 500).json({
    error: {
      message: isServerError ? 'Internal Server Error' : (err.message || 'Request failed'),
      status,
    }
  });
});

const PORT = Number(process.env.PORT) || 3000;
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 SamaFox API Server is running on port ${PORT}`);
});

export { io };
