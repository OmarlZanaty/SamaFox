"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const user_controller_1 = require("../controllers/user.controller");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const router = (0, express_1.Router)();
router.get('/me', auth_middleware_1.authMiddleware, user_controller_1.getMe);
router.put('/me', auth_middleware_1.authMiddleware, user_controller_1.updateProfile);
router.put('/me/gender-country', auth_middleware_1.authMiddleware, user_controller_1.updateGenderAndCountry);
router.get('/search', user_controller_1.searchUsers);
router.get('/country/:countryCode', user_controller_1.getUsersByCountry);
router.post('/:targetUserId/follow', auth_middleware_1.authMiddleware, user_controller_1.followUser);
router.post('/:targetUserId/unfollow', auth_middleware_1.authMiddleware, user_controller_1.unfollowUser);
router.get('/:userId/followers', user_controller_1.getFollowers);
router.get('/:userId/following', user_controller_1.getFollowing);
router.get('/:userId', user_controller_1.getUserById);
exports.default = router;
//# sourceMappingURL=user.routes.js.map