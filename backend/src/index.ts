import dotenv from 'dotenv';
dotenv.config();

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
import giftActionRoutes from './routes/gift.routes';
import giftRoutes from './gifts/gift.routes';
import messageRoutes from './routes/messages.routes';
import uploadRoutes from './routes/upload.routes';
import gameRoutes from './routes/game.routes';
import roomAdminRoutes from './routes/room-admin.routes';
import adminDashboardRoutes from './routes/adminDashboard.routes';
import adminDashAuthRoutes from './routes/admin-dashboard-auth.routes';
import storeRoutes from "./routes/store.routes";
import { initializeSocketHandlers } from './services/socket.service';
import adminProductRoutes from "./routes/adminProduct.routes";
import agencyRoutes from './agencies/agency.routes';
import searchRoutes from './search/search.routes';
import { resolvePublicDir } from './utils/publicDir';
import followRoutes from './follow/follow.routes';
import relationRoutes from './relations/relation.routes';
import notificationRoutes from './routes/notification.routes';

const app: Application = express();

app.set('trust proxy', true);

const normalizeOrigin = (origin: string) => origin.trim().replace(/\/+$/, '').toLowerCase();

const allowedOrigins = (process.env.CORS_ORIGIN ?? '')
  .split(',')
  .map((origin) => normalizeOrigin(origin))
  .filter(Boolean);

const isOriginAllowed = (origin?: string) => {
  if (!origin) return true; // non-browser clients / same-origin calls
  const normalizedOrigin = normalizeOrigin(origin);
  if (allowedOrigins.length === 0) {
    // If CORS_ORIGIN is not configured, do not block browser requests by default.
    // This prevents accidental 500s from the CORS middleware when dashboard is served from server IP/domain.
    return true;
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

app.use("/uploads", express.static("uploads"));
// passport (if you still use it elsewhere)
app.use(passport.initialize());

const publicDir = resolvePublicDir();

console.log(`📁 Serving static public directory from: ${publicDir}`);

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
app.use('/api/v1/gift-actions', giftActionRoutes);
app.use('/api/v1/messages', messageRoutes);
app.use('/api/v1/search', searchRoutes);
app.use('/api/v1/follow', followRoutes);
app.use('/api/v1/relations', relationRoutes);
app.use('/api/v1/notifications', notificationRoutes);

app.use('/api/v1/upload', uploadRoutes);
app.use('/upload', uploadRoutes); // backward-compatible path
app.use('/api/v1/room-admin', roomAdminRoutes);
app.use('/api/messages', messageRoutes); // ✅ same router

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

// error handler
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err.stack);
  res.status(err.status || 500).json({
    error: { message: err.message || 'Internal Server Error', status: err.status || 500 }
  });
});

const PORT = Number(process.env.PORT) || 3000;
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 SamaFox API Server is running on port ${PORT}`);
});

export { io };
