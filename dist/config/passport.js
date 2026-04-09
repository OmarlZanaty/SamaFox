"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const passport_1 = __importDefault(require("passport"));
const passport_google_oauth20_1 = require("passport-google-oauth20");
const prisma_1 = __importDefault(require("../utils/prisma"));
if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET) {
    passport_1.default.use(new passport_google_oauth20_1.Strategy({
        clientID: process.env.GOOGLE_CLIENT_ID,
        clientSecret: process.env.GOOGLE_CLIENT_SECRET,
        callbackURL: `${process.env.API_BASE_URL || 'http://localhost:3000'}/api/v1/auth/google/callback`,
        scope: ['profile', 'email']
    }, async (accessToken, refreshToken, profile, done) => {
        try {
            let user = await prisma_1.default.user.findUnique({
                where: { googleId: profile.id }
            });
            if (!user) {
                const email = profile.emails?.[0]?.value;
                if (email) {
                    user = await prisma_1.default.user.findUnique({
                        where: { email }
                    });
                    if (user) {
                        user = await prisma_1.default.user.update({
                            where: { id: user.id },
                            data: {
                                googleId: profile.id,
                                avatarUrl: user.avatarUrl || profile.photos?.[0]?.value
                            }
                        });
                    }
                }
                if (!user) {
                    user = await prisma_1.default.user.create({
                        data: {
                            googleId: profile.id,
                            email: profile.emails?.[0]?.value,
                            name: profile.displayName || 'User',
                            avatarUrl: profile.photos?.[0]?.value,
                            level: 1,
                            xp: 0,
                            coinsBalance: 100,
                            vipLevel: 0,
                            isAdmin: false
                        }
                    });
                }
            }
            return done(null, user);
        }
        catch (error) {
            return done(error, undefined);
        }
    }));
}
passport_1.default.deserializeUser(async (id, done) => {
    try {
        const user = await prisma_1.default.user.findUnique({
            where: { id }
        });
        done(null, user);
    }
    catch (error) {
        done(error, null);
    }
});
exports.default = passport_1.default;
//# sourceMappingURL=passport.js.map