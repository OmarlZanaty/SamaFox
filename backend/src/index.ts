import dotenv from 'dotenv';
dotenv.config();

import express, { Application } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { Server } from 'socket.io';
import passport from './config/passport';
import path from 'path';
import cookieParser from 'cookie-parser';

import chargingAgencyRoutes from './routes/charging-agency.routes';
import adminRoutes from './routes/admin.routes';
import authRoutes from './routes/auth.routes';
import userRoutes from './routes/user.routes';
import roomRoutes from './routes/room.routes';
import giftRoutes from './routes/gift.routes';
import messageRoutes from './routes/messages.routes';
import uploadRoutes from './routes/upload.routes';
import gameRoutes from './routes/game.routes';
import roomAdminRoutes from './routes/room-admin.routes';
import adminDashboardRoutes from './routes/adminDashboard.routes';
import adminDashAuthRoutes from './routes/admin-dashboard-auth.routes';
import storeRoutes from './routes/store.routes';
import { initializeSocketHandlers } from './services/socket.service';
import adminProductRoutes from './routes/adminProduct.routes';

const app: Application = express();

app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

app.use(passport.initialize());
app.use('/public', express.static(path.join(process.cwd(), 'public')));
app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));

app.use('/api/v1/admin-dashboard-auth', adminDashAuthRoutes);
app.use('/api/v1/admin-dashboard', adminDashboardRoutes);
app.use('/api/v1/store', storeRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/admin-products', adminProductRoutes);
app.use('/api/v1/games', gameRoutes);
app.use('/api/v1/charging-agencies', chargingAgencyRoutes);
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/rooms', roomRoutes);
app.use('/api/v1/gifts', giftRoutes);
app.use('/api/v1/messages', messageRoutes);
app.use('/api/v1/upload', uploadRoutes);
app.use('/api/v1/room-admin', roomAdminRoutes);
app.use('/api/messages', messageRoutes);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', message: 'SamaFox API is running' });
});

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: process.env.CORS_ORIGIN || '*',
    methods: ['GET', 'POST'],
    credentials: true,
  }
});

initializeSocketHandlers(io);

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err.stack);
  res.status(err.status || 500).json({
    success: false,
    message: err.message || 'Internal Server Error',
  });
});

const PORT = Number(process.env.PORT) || 3000;
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 SamaFox API Server is running on port ${PORT}`);
});

export { io };
