"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
const gifts = [
    { name: 'Red Rose', imageUrl: '🌹', animationUrl: null, priceCoins: 10, category: 'common', isActive: true },
    { name: 'Heart Balloon', imageUrl: '🎈', animationUrl: null, priceCoins: 15, category: 'common', isActive: true },
    { name: 'Chocolate Box', imageUrl: '🍫', animationUrl: null, priceCoins: 20, category: 'common', isActive: true },
    { name: 'Coffee', imageUrl: '☕', animationUrl: null, priceCoins: 25, category: 'common', isActive: true },
    { name: 'Love Letter', imageUrl: '💌', animationUrl: null, priceCoins: 50, category: 'rare', isActive: true },
    { name: 'Diamond Ring', imageUrl: '💍', animationUrl: null, priceCoins: 100, category: 'rare', isActive: true },
    { name: 'Champagne', imageUrl: '🍾', animationUrl: null, priceCoins: 75, category: 'rare', isActive: true },
    { name: 'Teddy Bear', imageUrl: '🧸', animationUrl: null, priceCoins: 60, category: 'rare', isActive: true },
    { name: 'Fireworks', imageUrl: '🎆', animationUrl: null, priceCoins: 250, category: 'epic', isActive: true },
    { name: 'Luxury Car', imageUrl: '🚗', animationUrl: null, priceCoins: 500, category: 'epic', isActive: true },
    { name: 'Diamond', imageUrl: '💎', animationUrl: null, priceCoins: 300, category: 'epic', isActive: true },
    { name: 'Trophy', imageUrl: '🏆', animationUrl: null, priceCoins: 400, category: 'epic', isActive: true },
    { name: 'Golden Crown', imageUrl: '👑', animationUrl: null, priceCoins: 1000, category: 'legendary', isActive: true },
    { name: 'Mansion', imageUrl: '🏰', animationUrl: null, priceCoins: 2000, category: 'legendary', isActive: true },
    { name: 'Private Jet', imageUrl: '✈️', animationUrl: null, priceCoins: 5000, category: 'legendary', isActive: true },
    { name: 'Yacht', imageUrl: '🛥️', animationUrl: null, priceCoins: 3000, category: 'legendary', isActive: true }
];
function seedGifts() {
    return __awaiter(this, void 0, void 0, function* () {
        console.log('🎁 Starting gift seeding...');
        try {
            yield prisma.gift.deleteMany({});
            console.log('✅ Cleared existing gifts');
            for (const gift of gifts) {
                yield prisma.gift.create({ data: gift });
                console.log(`✅ Created: ${gift.name} (${gift.priceCoins} coins)`);
            }
            console.log(`\n🎉 Successfully seeded ${gifts.length} gifts!`);
        }
        catch (error) {
            console.error('❌ Error:', error);
            throw error;
        }
        finally {
            yield prisma.$disconnect();
        }
    });
}
seedGifts().catch((error) => { console.error(error); process.exit(1); });
