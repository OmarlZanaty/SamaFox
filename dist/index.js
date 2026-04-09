"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.io = void 0;
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const http_1 = require("http");
const socket_io_1 = require("socket.io");
const passport_1 = __importDefault(require("./config/passport"));
const path_1 = __importDefault(require("path"));
const cookie_parser_1 = __importDefault(require("cookie-parser"));
const charging_agency_routes_1 = __importDefault(require("./routes/charging-agency.routes"));
const admin_routes_1 = __importDefault(require("./routes/admin.routes"));
const auth_routes_1 = __importDefault(require("./routes/auth.routes"));
const user_routes_1 = __importDefault(require("./routes/user.routes"));
const room_routes_1 = __importDefault(require("./routes/room.routes"));
const gift_routes_1 = __importDefault(require("./routes/gift.routes"));
const messages_routes_1 = __importDefault(require("./routes/messages.routes"));
const upload_routes_1 = __importDefault(require("./routes/upload.routes"));
const game_routes_1 = __importDefault(require("./routes/game.routes"));
const room_admin_routes_1 = __importDefault(require("./routes/room-admin.routes"));
const adminDashboard_routes_1 = __importDefault(require("./routes/adminDashboard.routes"));
const admin_dashboard_auth_routes_1 = __importDefault(require("./routes/admin-dashboard-auth.routes"));
const store_routes_1 = __importDefault(require("./routes/store.routes"));
const socket_service_1 = require("./services/socket.service");
const adminProduct_routes_1 = __importDefault(require("./routes/adminProduct.routes"));
const app = (0, express_1.default)();
app.use((0, cors_1.default)({
    origin: process.env.CORS_ORIGIN || '*',
    credentials: true,
}));
app.use(express_1.default.json());
app.use(express_1.default.urlencoded({ extended: true }));
app.use((0, cookie_parser_1.default)());
app.use("/api/v1/store", store_routes_1.default);
app.use('/api/v1/admin', admin_routes_1.default);
app.use((0, cookie_parser_1.default)());
app.use("/api/v1/admin-products", adminProduct_routes_1.default);
app.use(express_1.default.json());
app.use(express_1.default.urlencoded({ extended: true }));
app.use("/uploads", express_1.default.static("uploads"));
app.use(passport_1.default.initialize());
app.use('/public', express_1.default.static(path_1.default.join(process.cwd(), 'public')));
app.use('/uploads', express_1.default.static(path_1.default.join(process.cwd(), 'uploads')));
app.use('/api/v1/admin-dashboard-auth', admin_dashboard_auth_routes_1.default);
app.use('/api/v1/admin-dashboard', adminDashboard_routes_1.default);
app.use('/api/v1/games', game_routes_1.default);
app.use('/api/v1/charging-agencies', charging_agency_routes_1.default);
app.use('/api/v1/auth', auth_routes_1.default);
app.use('/api/v1/users', user_routes_1.default);
app.use('/api/v1/rooms', room_routes_1.default);
app.use('/api/v1/gifts', gift_routes_1.default);
app.use('/api/v1/messages', messages_routes_1.default);
app.use('/api/v1/upload', upload_routes_1.default);
app.use('/api/v1/room-admin', room_admin_routes_1.default);
app.use('/api/messages', messages_routes_1.default);
app.get('/health', (_req, res) => {
    res.json({ status: 'ok', message: 'SamaFox API is running' });
});
const httpServer = (0, http_1.createServer)(app);
const io = new socket_io_1.Server(httpServer, {
    cors: {
        origin: process.env.CORS_ORIGIN || '*',
        methods: ['GET', 'POST'],
        credentials: true,
    }
});
exports.io = io;
(0, socket_service_1.initializeSocketHandlers)(io);
app.use((err, _req, res, _next) => {
    console.error(err.stack);
    res.status(err.status || 500).json({
        error: { message: err.message || 'Internal Server Error', status: err.status || 500 }
    });
});
const PORT = Number(process.env.PORT) || 3000;
httpServer.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 SamaFox API Server is running on port ${PORT}`);
});
//# sourceMappingURL=index.js.map