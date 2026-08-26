import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';
import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { nextDisplayId } from '../utils/displayId';
import { grantAutoItemsToUser } from '../services/auto-grant.service';

async function createUserWithDisplayId(
  tx: Prisma.TransactionClient,
  userData: Omit<Prisma.UserCreateInput, 'displayId'>,
) {
  const displayId = await nextDisplayId(tx); // 6-digit, unique
  const user = await tx.user.create({ data: { ...userData, displayId } });
  // منتجات "جميع المستخدمين" تُمنح للحساب الجديد تلقائياً.
  try {
    await grantAutoItemsToUser(user.id, tx);
  } catch (e) {
    console.warn('auto-grant on google register failed:', e);
  }
  return user;
}

// Google OAuth Strategy
if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET) {
  passport.use(
    new GoogleStrategy(
      {
        clientID: process.env.GOOGLE_CLIENT_ID,
        clientSecret: process.env.GOOGLE_CLIENT_SECRET,
        callbackURL: `${process.env.API_BASE_URL || 'http://localhost:3000'}/api/v1/auth/google/callback`,
        scope: ['profile', 'email']
      },
      async (accessToken, refreshToken, profile, done ) => {
        try {
          // Check if user exists with Google ID
          let user = await prisma.user.findUnique({
            where: { googleId: profile.id }
          });

          if (!user) {
            // Check if user exists with same email
            const email = profile.emails?.[0]?.value;
            if (email) {
              user = await prisma.user.findUnique({
                where: { email }
              });

              // If user exists with email, link Google account
              if (user) {
                user = await prisma.user.update({
                  where: { id: user.id },
                  data: {
                    googleId: profile.id,
                    avatarUrl: user.avatarUrl || profile.photos?.[0]?.value
                  }
                });
              }
            }

            // Create new user if doesn't exist
            if (!user) {
              user = await prisma.$transaction(async (tx) => {
                return createUserWithDisplayId(tx, {
                  googleId: profile.id,
                  email: profile.emails?.[0]?.value,
                  name: profile.displayName || 'User',
                  avatarUrl: profile.photos?.[0]?.value,
                  level: 1,
                  xp: 0,
                  coinsBalance: 100, // Welcome bonus
                  vipLevel: 0,
                  isAdmin: false
                });
              });
            }
          }

          return done(null, user);
        } catch (error) {
          return done(error as Error, undefined);
        }
      }
    )
  );
}

// Deserialize user from session
passport.deserializeUser(async (id: number, done) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id }
    });
    done(null, user);
  } catch (error) {
    done(error, null);
  }
});

export default passport;
