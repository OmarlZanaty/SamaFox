// 2026-10-21 (owner: "اعمل كله") — FRUIT WHEEL (77):
//   * no per-card bet ceiling (maxBet 1e9; the pool-coverage check still guards payouts)
//   * programShareBp 3000 → 2000: 10% of every stake stays in the pool so it grows
//   * GAME_POOL:fruitwheel +10,000,000 from PROGRAM (same path as fundGamePool), audited
// Run on the server from /srv/samafox/backend:  node fruitwheel-20261021.cjs [--apply]
// Imports only prisma-level services — nothing that reaches dist/index.js.
const prisma = require('./dist/utils/prisma').default;
const cfg = require('./dist/services/gameConfig.service');
const acc = require('./dist/services/economyAccounts.service');
const audit = require('./dist/services/adminAudit.service');

const APPLY = process.argv.includes('--apply');
const GAME = 'fruitwheel';
const ADMIN = 32;
const FUND = 10_000_000;
const REASON = 'طلب العميل 2026-10-21: بدون حد للرهان + صندوق أكبر';

(async () => {
  const before = await cfg.getGameSettings(GAME);
  const pool = acc.gamePoolAccount(GAME);
  const poolBefore = Number(await acc.readBalance(prisma, pool));
  console.log('before', { maxBet: before.maxBet, programShareBp: before.programShareBp, rtpTargetBp: before.rtpTargetBp, pool: poolBefore });
  if (!APPLY) { console.log('dry run — pass --apply'); process.exit(0); }

  const after = await cfg.setGameSettings(GAME, { maxBet: 1_000_000_000, programShareBp: 2000 });
  await audit.recordAdminAudit({
    adminId: ADMIN, action: 'GAME_SETTINGS_UPDATE', targetType: 'game', targetId: GAME,
    before: { maxBet: before.maxBet, programShareBp: before.programShareBp },
    after: { maxBet: after.maxBet, programShareBp: after.programShareBp }, reason: REASON,
  });

  const out = await prisma.$transaction(async (tx) => {
    await acc.debitAccount(tx, acc.PROGRAM_ACCOUNT, FUND, { kind: 'POOL_FUNDING', refType: 'game', refId: GAME, userId: ADMIN }, { allowNegative: true });
    return Number(await acc.creditAccount(tx, pool, FUND, { kind: 'POOL_FUNDING', refType: 'game', refId: GAME, userId: ADMIN }));
  });
  await audit.recordAdminAudit({
    adminId: ADMIN, action: audit.AUDIT_ACTIONS.GAME_POOL_FUND, targetType: 'game_pool', targetId: GAME,
    before: { poolBalance: out - FUND }, after: { poolBalance: out, funded: FUND }, reason: REASON,
  });
  console.log('after', { maxBet: after.maxBet, programShareBp: after.programShareBp, pool: out });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
