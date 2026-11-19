import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
let user: any;
let audits: any[];
let vipCap: number | null;
let levelCap: number | null;
let vipRows: any[];
let levelRows: any[];
let auditFails: boolean;
let grants: any[] = [];
const config = (vip: boolean) => ({
  aggregate: async () => ({ _max: { level: vip ? vipCap : levelCap } }),
  findMany: async ({ where }: any = {}) => (vip ? vipRows : levelRows).filter(row =>
    where?.level?.not != null ? row.level !== where.level.not : row.threshold != null),
  findUnique: async ({ where }: any) => (vip ? vipRows : levelRows).find(row => row.level === where.level) ?? null,
  delete: async ({ where }: any) => {
    if (vip) vipRows = vipRows.filter(row => row.level !== where.level);
    else levelRows = levelRows.filter(row => row.level !== where.level);
  },
});
const db: any = {
  user: {
    findUnique: async () => ({ ...user }),
    update: async ({ data }: any) => Object.assign(user, data),
    count: async ({ where }: any) => Object.entries(where).every(([key, value]) => user[key] === value) ? 1 : 0,
    updateMany: async ({ where, data }: any) => {
      for (const [key, cond] of Object.entries<any>(where ?? {})) {
        if (cond && typeof cond === 'object' ? !(user[key] > cond.gt) : user[key] !== cond) return { count: 0 };
      }
      Object.assign(user, data); return { count: 1 };
    },
  },
  temporaryEntitlement: {
    updateMany: async ({ where, data }: any) => {
      const hit = grants.filter(g => g.type === where.type && g.status === where.status && g.value >= where.value.gte);
      hit.forEach(g => Object.assign(g, data));
      return { count: hit.length };
    },
  },
  vipLevelConfig: config(true), levelConfig: config(false),
  $transaction: async (fn: any) => {
    const snapshot = { user: { ...user }, vipRows: [...vipRows], levelRows: [...levelRows], grants: grants.map(g => ({ ...g })) };
    try { return await fn(db); }
    catch (error) { user = snapshot.user; vipRows = snapshot.vipRows; levelRows = snapshot.levelRows; grants = snapshot.grants; throw error; }
  },
};
stub('utils/prisma', { __esModule: true, default: db });
for (const module of [
  'controllers/charging-agency.controller', 'agencies/agency.controller',
  'utils/resolveUserByPublicId', 'agencies/oneAgencyRule', 'services/agencyIdentity.service',
  'gifts/catalogCache', 'utils/banGuard', 'services/socket.service',
  'middlewares/deviceBan.middleware', 'services/agencyReward.service',
  'services/targetMovement.service', 'utils/targetLock', 'utils/coinFreeze',
  'services/vipStyle.service',
]) stub(module, {});
stub('services/notification.service', { createNotification: async () => {} });
stub('gifts/catalogCache', { bumpCatalogVersion: async () => {} });
stub('services/vipStyle.service', { invalidateVipStyleCache: () => {} });
stub('controllers/achievement.controller', { checkAchievements: async () => {} });
stub('services/adminAudit.service', {
  auditContext: () => ({}), recordAdminAudit: async (row: any) => audits.push(row),
  recordAdminAuditStrict: async (_tx: any, row: any) => {
    if (auditFails) throw new Error('audit unavailable');
    audits.push(row);
  },
});
const vip: typeof import('../vip.service') = require('../vip.service');
const xp: typeof import('../xp.service') = require('../xp.service');
const { adminUpdateUserProgression, adminDeleteVipLevel, adminDeleteLevel } = require('../../controllers/adminDashboard.controller');

beforeEach(() => {
  user = { id: 1, level: 1, vipLevel: 0, xp: 0, totalRecharge: 0 };
  audits = []; vipCap = null; levelCap = null;
  vipRows = []; levelRows = []; auditFails = false; grants = [];
  vip.invalidateVipMaxCache(); xp.invalidateLevelMaxCache();
});
async function set(body: any) {
  let status = 200;
  let payload: any;
  const res = { status(n: number) { status = n; return res; }, json(data: any) { payload = data; return res; } };
  await adminUpdateUserProgression({ params: { id: '1' }, userId: 9, body }, res);
  assert.equal(status, 200);
  return payload;
}

test('VIP 30 -> 6 resets recharge and requires the full gap to VIP 7', async () => {
  await set({ vipLevel: 30 });
  const oldTotal = user.totalRecharge;
  const response = await set({ vipLevel: 6 });
  assert.equal(user.totalRecharge, vip.vipRechargeFloor(6, new Map()));
  assert.equal(response.data.totalRecharge, user.totalRecharge);
  assert.equal(audits[1].before.totalRecharge, oldTotal);
  assert.equal(audits[1].after.totalRecharge, user.totalRecharge);
  user.totalRecharge++;
  assert.equal((await vip.evaluateVip(1)).vipLevel, 6);
  user.totalRecharge = vip.vipThreshold(7) - 1;
  assert.equal((await vip.evaluateVip(1)).vipLevel, 6);
  user.totalRecharge++;
  assert.equal((await vip.evaluateVip(1)).vipLevel, 7);
});

test('level 30 -> 6 resets XP; explicit XP wins; base tiers reset to zero', async () => {
  await set({ level: 30 });
  await set({ level: 6 });
  assert.equal(user.xp, xp.levelXpFloor(6, new Map()));
  assert.equal((await xp.awardUserXP(1, 1)).level, 6);
  const remaining = xp.levelXpFloor(7, new Map()) - user.xp;
  assert.equal((await xp.awardUserXP(1, remaining - 1)).level, 6);
  assert.equal((await xp.awardUserXP(1, 1)).level, 7);
  await set({ level: 6, xp: 42 });
  assert.equal(user.xp, 42);
  await set({ level: 1, vipLevel: 0 });
  assert.equal(user.xp, 0);
  assert.equal(user.totalRecharge, 0);
});

test('configured maxima cap manual and earned levels without demoting existing users', async () => {
  vipCap = 6; levelCap = 8;
  await set({ vipLevel: 30, level: 30 });
  assert.equal(user.vipLevel, 6);
  assert.equal(user.level, 8);
  user.totalRecharge = 1e12;
  assert.equal((await vip.evaluateVip(1)).vipLevel, 6);
  assert.equal((await xp.awardUserXP(1, 1e9)).level, 8);
  user.vipLevel = 30; user.level = 30;
  assert.equal((await vip.evaluateVip(1)).vipLevel, 30);
  assert.equal((await xp.awardUserXP(1, 1)).level, 30);
  assert.equal(vip.computeVipLevelWithOverrides(1e12, new Map([[6, 100]]), 6), 6);
  assert.equal(xp.calculateLevelWithOverrides(1e9, new Map([[8, 100]]), 8), 8);
});

test('maximum caches invalidate and empty configuration retains legacy curves', async () => {
  vipCap = 6; levelCap = 8;
  assert.equal(await vip.getVipMaxLevel(), 6);
  assert.equal(await xp.getLevelMaxLevel(), 8);
  vipCap = null; levelCap = null;
  assert.equal(await vip.getVipMaxLevel(), 6);
  vip.invalidateVipMaxCache(); xp.invalidateLevelMaxCache();
  assert.equal(await vip.getVipMaxLevel(), null);
  assert.equal(await xp.getLevelMaxLevel(), null);
  assert.equal(vip.computeVipLevelWithOverrides(vip.vipThreshold(9), new Map(), null), 9);
  assert.equal(xp.calculateLevelWithOverrides(10000, new Map(), null), 11);
});

test('occupied tier deletion requires force, resets counters and audits the deleted row', async () => {
  for (const vipTier of [true, false]) {
    vipRows = levelRows = [{ level: 6, threshold: 1000 }, { level: 7, threshold: 2000 }];
    user = { ...user, vipLevel: 7, level: 7, xp: 9000, totalRecharge: 9000000 };
    let status = 200; let payload: any;
    const res = { status(n: number) { status = n; return res; }, json(value: any) { payload = value; return res; } };
    const handler = vipTier ? adminDeleteVipLevel : adminDeleteLevel;
    const req = { params: { level: '7' }, query: {} as any, userId: 9 };
    await handler(req, res);
    assert.equal(status, 409);
    assert.equal(payload.count, 1);
    assert.equal((vipTier ? vipRows : levelRows).length, 2);
    req.query.force = '1'; status = 200;
    await handler(req, res);
    assert.equal(status, 200);
    assert.equal(user[vipTier ? 'vipLevel' : 'level'], 6);
    // History is never lowered: only the displayed tier moves.
    assert.equal(user.totalRecharge, 9000000);
    assert.equal(user.xp, 9000);
    assert.deepEqual(audits[audits.length - 1].before, { level: 7, threshold: 2000 });
    assert.equal(audits[audits.length - 1].action, vipTier ? 'VIP_LEVEL_DELETE' : 'LEVEL_DELETE');
  }
});

test('strict audit failure rolls back forced deletion and user movement', async () => {
  vipRows = [{ level: 6, threshold: 1000 }, { level: 7, threshold: 2000 }];
  user.vipLevel = 7; user.totalRecharge = 9000000; auditFails = true;
  let status = 200;
  const res = { status(n: number) { status = n; return res; }, json() { return res; } };
  await adminDeleteVipLevel({ params: { level: '7' }, query: { force: '1' }, userId: 9 }, res);
  assert.equal(status, 500);
  assert.equal(vipRows.length, 2);
  assert.equal(user.vipLevel, 7);
  assert.equal(user.totalRecharge, 9000000);
});

test('saving unchanged prefilled fields keeps progress; only changed fields reset counters', async () => {
  user = { id: 1, level: 5, vipLevel: 3, xp: 5000, totalRecharge: 2_000_000 };
  // VIP unchanged, only xp edited: totalRecharge must survive.
  await set({ level: 5, xp: 7000, vipLevel: 3 });
  assert.equal(user.xp, 7000);
  assert.equal(user.totalRecharge, 2_000_000);
  // Level changed, xp resent unchanged: xp resets to the new level floor.
  await set({ level: 9, xp: 7000, vipLevel: 3 });
  assert.equal(user.xp, xp.levelXpFloor(9, new Map()));
  assert.equal(user.totalRecharge, 2_000_000);
  // VIP changed: recharge resets to that tier's floor.
  await set({ level: 9, xp: user.xp, vipLevel: 4 });
  assert.equal(user.totalRecharge, vip.vipRechargeFloor(4, new Map()));
});

test('users above the cap are not clamped when another field is edited', async () => {
  vipCap = 6; levelCap = 8;
  user = { id: 1, level: 30, vipLevel: 30, xp: 100, totalRecharge: 5e9 };
  await set({ level: 30, vipLevel: 30, xp: 200 });
  assert.equal(user.level, 30);
  assert.equal(user.vipLevel, 30);
  assert.equal(user.totalRecharge, 5e9);
  assert.equal(user.xp, 200);
  await set({ vipLevel: 40 });
  assert.equal(user.vipLevel, 6);
});

test('forced deletion leaves recharge/xp untouched and caps active timed grants', async () => {
  vipRows = [{ level: 6, threshold: 1000 }, { level: 7, threshold: 2000 }];
  // Timed VIP 7 holder with little recharge must NOT be raised to the VIP 6 floor.
  user = { ...user, vipLevel: 7, totalRecharge: 50 };
  grants = [{ type: 'VIP', status: 'ACTIVE', value: 7 }, { type: 'VIP', status: 'ACTIVE', value: 3 }, { type: 'LEVEL', status: 'ACTIVE', value: 7 }];
  let status = 200;
  const res = { status(n: number) { status = n; return res; }, json() { return res; } };
  await adminDeleteVipLevel({ params: { level: '7' }, query: { force: '1' }, userId: 9 }, res);
  assert.equal(status, 200);
  assert.equal(user.vipLevel, 6);
  assert.equal(user.totalRecharge, 50);
  assert.deepEqual(grants.map(g => g.value), [6, 3, 7]);
});

test('only the highest configured tier can be deleted', async () => {
  for (const handler of [adminDeleteVipLevel, adminDeleteLevel]) {
    vipRows = levelRows = [{ level: 5, threshold: 500 }, { level: 6, threshold: 1000 }, { level: 7, threshold: 2000 }];
    let status = 200; let payload: any;
    const res = { status(n: number) { status = n; return res; }, json(v: any) { payload = v; return res; } };
    await handler({ params: { level: '6' }, query: { force: '1' }, userId: 9 }, res);
    assert.equal(status, 409);
    assert.equal(payload.message, 'احذف أعلى مستوى الأول');
    assert.equal(vipRows.length, 3);
  }
});
