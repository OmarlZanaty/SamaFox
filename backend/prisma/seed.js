"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const prisma_1 = require("../src/generated/prisma");
const prisma = new prisma_1.PrismaClient();
async function main() {
    console.log('🌱 Seeding database...');
    const users = await Promise.all([
        prisma.user.create({
            data: {
                name: 'Ahmed Saleh',
                email: 'ahmed@example.com',
                bio: 'Welcome to my profile!',
                level: 5,
                xp: 1250,
                coinsBalance: 500,
                vipLevel: 1,
                countryCode: 'EG'
            }
        }),
        prisma.user.create({
            data: {
                name: 'Mona Ali',
                phone: '+201234567890',
                bio: 'Music lover 🎵',
                level: 3,
                xp: 750,
                coinsBalance: 300,
                vipLevel: 0,
                countryCode: 'EG'
            }
        }),
        prisma.user.create({
            data: {
                name: 'Omar Hassan',
                email: 'omar@example.com',
                bio: 'Let\'s chat!',
                level: 4,
                xp: 980,
                coinsBalance: 450,
                vipLevel: 0,
                countryCode: 'SA'
            }
        })
    ]);
    console.log(`✅ Created ${users.length} users`);
    const rooms = await Promise.all([
        prisma.room.create({
            data: {
                name: 'Friends Lounge',
                description: 'A place for friends to hang out',
                type: 'public',
                maxSeats: 8,
                ownerId: users[0].id,
                isActive: true
            }
        }),
        prisma.room.create({
            data: {
                name: 'Music Lovers',
                description: 'Share your favorite music',
                type: 'public',
                maxSeats: 12,
                ownerId: users[1].id,
                isActive: true
            }
        }),
        prisma.room.create({
            data: {
                name: 'Chill Zone',
                description: 'Relax and chat',
                type: 'public',
                maxSeats: 9,
                ownerId: users[2].id,
                isActive: true
            }
        })
    ]);
    console.log(`✅ Created ${rooms.length} rooms`);
    await Promise.all([
        prisma.roomMember.create({
            data: {
                userId: users[0].id,
                roomId: rooms[0].id,
                role: 'owner'
            }
        }),
        prisma.roomMember.create({
            data: {
                userId: users[1].id,
                roomId: rooms[1].id,
                role: 'owner'
            }
        }),
        prisma.roomMember.create({
            data: {
                userId: users[2].id,
                roomId: rooms[2].id,
                role: 'owner'
            }
        }),
        prisma.roomMember.create({
            data: {
                userId: users[1].id,
                roomId: rooms[0].id,
                role: 'member'
            }
        }),
        prisma.roomMember.create({
            data: {
                userId: users[2].id,
                roomId: rooms[0].id,
                role: 'member'
            }
        })
    ]);
    console.log('✅ Added room members');
    const gifts = await Promise.all([
        prisma.gift.create({
            data: {
                name: 'Red Rose',
                imageUrl: '/gifts/rose.png',
                priceCoins: 10,
                category: 'instant',
                isActive: true
            }
        }),
        prisma.gift.create({
            data: {
                name: 'Diamond Ring',
                imageUrl: '/gifts/diamond-ring.png',
                animationUrl: '/gifts/diamond-ring.json',
                priceCoins: 100,
                category: 'animated',
                isActive: true
            }
        }),
        prisma.gift.create({
            data: {
                name: 'Luxury Car',
                imageUrl: '/gifts/car.png',
                animationUrl: '/gifts/car.json',
                priceCoins: 500,
                category: 'special',
                isActive: true
            }
        }),
        prisma.gift.create({
            data: {
                name: 'Fireworks',
                imageUrl: '/gifts/fireworks.png',
                animationUrl: '/gifts/fireworks.json',
                priceCoins: 250,
                category: 'animated',
                isActive: true
            }
        }),
        prisma.gift.create({
            data: {
                name: 'Heart Balloon',
                imageUrl: '/gifts/balloon.png',
                priceCoins: 25,
                category: 'instant',
                isActive: true
            }
        })
    ]);
    console.log(`✅ Created ${gifts.length} gifts`);
    await Promise.all([
        prisma.relationship.create({
            data: {
                followerId: users[0].id,
                followingId: users[1].id,
                type: 'fan',
                status: 'accepted'
            }
        }),
        prisma.relationship.create({
            data: {
                followerId: users[0].id,
                followingId: users[2].id,
                type: 'fan',
                status: 'accepted'
            }
        }),
        prisma.relationship.create({
            data: {
                followerId: users[1].id,
                followingId: users[0].id,
                type: 'fan',
                status: 'accepted'
            }
        })
    ]);
    console.log('✅ Created relationships');
    console.log('🎉 Database seeding completed!');
}
main()
    .catch((e) => {
    console.error('❌ Seeding error:', e);
    process.exit(1);
})
    .finally(async () => {
    await prisma.$disconnect();
});
//# sourceMappingURL=seed.js.map