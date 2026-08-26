import prisma from "../utils/prisma";

/**
 * منتجات "جميع المستخدمين": أي منتج مُنح من لوحة التحكم لكل المستخدمين يبقى
 * محمولاً بالراية `grantToAll`, فيستلمه كل حساب جديد تلقائياً بنفس المدة
 * المحددة في اللوحة (null = أبدي).
 *
 * يقبل عميل معاملة (tx) لينفَّذ داخل نفس معاملة إنشاء المستخدم.
 */
export async function grantAutoItemsToUser(userId: number, client: any = prisma) {
  const items = await client.item.findMany({
    where: { grantToAll: true } as any,
    select: { id: true, durationDays: true } as any,
  });
  if (!items.length) return 0;

  const now = Date.now();
  const result = await client.userItem.createMany({
    data: items.map((i: any) => ({
      userId,
      itemId: i.id,
      expiresAt:
        i.durationDays && i.durationDays > 0
          ? new Date(now + i.durationDays * 24 * 60 * 60 * 1000)
          : null,
    })),
    skipDuplicates: true,
  });
  return result.count;
}
