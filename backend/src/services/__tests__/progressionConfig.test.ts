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
    updateMany: async ({ data }: any) => { Object.assign(user, data); return { count: 1 }; },
  },
  vipLevelConfig: config(true), levelConfig: config(false),
  $transaction: async (fn: any) => {
    const snapshot = { user: { ...user }, vipRows: [...vipRows], levelRows: [...levelRows] };
    try { return await fn(db); }
    catch (error) { user = snapshot.user; vipRows = snapshot.vipRows; levelRows = snapshot.levelRows; throw error; }
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
  vipRows = []; levelRows = []; auditFails = false;
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
    const overrides = new Map([[6, 1000]]);
    assert.equal(user[vipTier ? 'totalRecharge' : 'xp'], vipTier ? vip.vipRechargeFloor(6, overrides) : xp.levelXpFloor(6, overrides));
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
