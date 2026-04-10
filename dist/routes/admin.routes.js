"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const adminController = __importStar(require("../controllers/admin.controller"));
const router = (0, express_1.Router)();
const adminMiddleware = async (req, res, next) => {
    try {
        const prisma = require('../utils/prisma').default;
        const user = await prisma.user.findUnique({
            where: { id: req.userId }
        });
        if (!user || !user.isAdmin) {
            return res.status(403).json({ message: 'Access denied. Admin only.' });
        }
        next();
    }
    catch (error) {
        res.status(500).json({ message: 'Server error' });
    }
};
router.use(auth_middleware_1.authMiddleware);
router.use(adminMiddleware);
router.get('/dashboard', adminController.getDashboardStats);
router.get('/users', adminController.getAllUsers);
router.post('/users/:userId/coins/add', adminController.addCoins);
router.post('/users/:userId/coins/remove', adminController.removeCoins);
router.put('/users/:userId/admin', adminController.toggleAdminStatus);
router.put('/users/:userId/ban', adminController.toggleUserBan);
router.delete('/rooms/:roomId', adminController.deleteRoom);
router.delete('/products/:id', adminController.deleteProduct);
router.get('/transactions', adminController.getAllTransactions);
exports.default = router;
//# sourceMappingURL=admin.routes.js.map