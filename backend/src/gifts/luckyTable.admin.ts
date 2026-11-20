import { Router } from 'express';
import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { recordAdminAuditStrict, auditContext } from '../services/adminAudit.service';
import { drawTable, tablePayout, TABLE_TIERS, validTable, type TableRow } from './luckyTable';

export const luckyTableAdmin = Router();
luckyTableAdmin.get('/', async (_req, res, next) => {
  try {
    const rows = await prisma.$queryRaw<TableRow[]>`SELECT * FROM lucky_control_rows ORDER BY "giftValue"`;
    res.json({ success: true, data: { rows, tiers: TABLE_TIERS } });
  } catch (e) { next(e); }
});
luckyTableAdmin.put('/:value', async (req: any, res, next) => {
  try {
    const value = Number(req.params.value), thresholds = req.body?.thresholds;
    if (!validTable(value, thresholds)) return res.status(400).json({ message: 'Supply a positive gift value and 14 positive integer throw counts' });
    await prisma.$transaction(async (tx) => {
      const before = await tx.$queryRaw<TableRow[]>`SELECT * FROM lucky_control_rows WHERE "giftValue" = ${value}`;
      await tx.$executeRaw(Prisma.sql`INSERT INTO lucky_control_rows ("giftValue", thresholds)
        VALUES (${value}, ARRAY[${Prisma.join(thresholds)}]::integer[])
        ON CONFLICT ("giftValue") DO UPDATE SET thresholds = EXCLUDED.thresholds,
          tier = 0, counter = 0, "testTier" = 0, "testCounter" = 0`);
      await recordAdminAuditStrict(tx, { adminId: Number((req as any).userId), action: 'LUCKY_TABLE_UPSERT', targetType: 'lucky_table', targetId: value, before: before[0] ?? null, after: { giftValue: value, thresholds }, ...auditContext(req) });
    });
    return res.json({ success: true });
  } catch (e) { return next(e); }
});
luckyTableAdmin.delete('/:value', async (req: any, res, next) => {
  try {
    const value = Number(req.params.value);
    if (!Number.isInteger(value) || value < 1) return res.status(400).json({ message: 'Invalid gift value' });
    await prisma.$transaction(async (tx) => {
      const before = await tx.$queryRaw<TableRow[]>`SELECT * FROM lucky_control_rows WHERE "giftValue" = ${value}`;
      await tx.$executeRaw`DELETE FROM lucky_control_rows WHERE "giftValue" = ${value}`;
      await recordAdminAuditStrict(tx, { adminId: Number((req as any).userId), action: 'LUCKY_TABLE_DELETE', targetType: 'lucky_table', targetId: value, before: before[0] ?? null, after: null, ...auditContext(req) });
    });
    return res.json({ success: true });
  } catch (e) { return next(e); }
});
luckyTableAdmin.post('/reset', async (req: any, res, next) => {
  try {
    const value = req.body?.giftValue;
    if (value != null && (!Number.isInteger(value) || value < 1)) return res.status(400).json({ message: 'Invalid gift value' });
    await prisma.$transaction(async (tx) => {
      if (value == null) await tx.$executeRaw`UPDATE lucky_control_rows SET tier=0, counter=0, "testTier"=0, "testCounter"=0`;
      else await tx.$executeRaw`UPDATE lucky_control_rows SET tier=0, counter=0, "testTier"=0, "testCounter"=0 WHERE "giftValue"=${value}`;
      await recordAdminAuditStrict(tx, { adminId: Number((req as any).userId), action: 'LUCKY_TABLE_RESET', targetType: 'lucky_table', targetId: value ?? 0, before: null, after: { giftValue: value ?? 'all' }, ...auditContext(req) });
    });
    return res.json({ success: true });
  } catch (e) { return next(e); }
});
// Test mode is deliberately an admin-only virtual throw: no gift, wallet, or live pool mutation.
luckyTableAdmin.post('/test', async (req: any, res, next) => {
  try {
    const { giftValue, quantity = 1, mics = 1 } = req.body ?? {};
    if (![giftValue, quantity, mics].every(n => Number.isInteger(n) && n > 0) || quantity * mics > 1_000_000)
      return res.status(400).json({ message: 'Invalid gift value, quantity or mic count' });
    const result = await prisma.$transaction(async (tx) => {
      const r = await drawTable(tx, giftValue, quantity * mics, true, mics);
      if (r) await recordAdminAuditStrict(tx, { adminId: Number(req.userId), action: 'LUCKY_TABLE_TEST', targetType: 'lucky_table', targetId: giftValue, before: null, after: { quantity, mics }, ...auditContext(req) });
      return r;
    });
    if (!result) return res.status(404).json({ message: 'No table row for this gift value' });
    return res.json({ success: true, data: { ...result, virtualPayout: tablePayout(result.multiplier, giftValue, mics) } });
  } catch (e) { return next(e); }
});
