"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const game_controller_1 = require("../controllers/game.controller");
const router = (0, express_1.Router)();
router.post('/dice/play', auth_middleware_1.authenticate, game_controller_1.playDice);
router.get('/leaderboard', game_controller_1.getLeaderboard);
router.get('/stats/:userId', game_controller_1.getUserGameStats);
exports.default = router;
//# sourceMappingURL=game.routes.js.map