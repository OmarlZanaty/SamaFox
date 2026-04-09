"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const auth_middleware_1 = require("../middlewares/auth.middleware");
const adminDashboard_controller_1 = require("../controllers/adminDashboard.controller");
const router = express_1.default.Router();
router.get('/overview', auth_middleware_1.authenticate, adminDashboard_controller_1.adminDashboardOverview);
router.get('/users', auth_middleware_1.authenticate, adminDashboard_controller_1.adminDashboardListUsers);
router.get('/rooms', auth_middleware_1.authenticate, adminDashboard_controller_1.adminDashboardListRooms);
router.get('/charging-agencies', auth_middleware_1.authenticate, adminDashboard_controller_1.adminDashboardListChargingAgencies);
router.patch('/charging-agencies/:id/status', auth_middleware_1.authenticate, adminDashboard_controller_1.adminDashboardUpdateAgencyStatus);
exports.default = router;
//# sourceMappingURL=adminDashboard.routes.js.map