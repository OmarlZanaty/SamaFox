/**
 * End-to-end tests for نظام الإدارة والصلاحيات (2026-10-04), against a REAL
 * PostgreSQL and the REAL compiled server (dist/index.js), over HTTP and
 * Socket.IO.
 *
 *   E2E_DATABASE_URL=postgresql://…/samafox_e2e npm run test:e2e
 *
 * The database is WIPED — the suite refuses anything that is not localhost.
 * Build first (`npx tsc`). One test waits for the 60-second expiry job.
 */
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import path from 'node:path';

const DB = process.env.E2E_DATABASE_URL ?? '';
const SKIP = !/^postgres(ql)?:\/\/[^@]+@(localhost|127\.0\.0\.1)[:/]/.test(DB);
if (!SKIP) process.env.DATABASE_URL = DB;

/* eslint-disable @typescript-eslint/no-var-requires */
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const { io: ioc } = require('socket.io-client');

const PORT = 39124;
const BASE = `http://127.0.0.1:${PORT}/api/v1`;
const SECRET = 'e2e-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const REFRESH = 'e2e-refresh-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const DAY = 86_400_000;

const prisma = SKIP ? null : new PrismaClient({ datasources: { db: { url: DB } } });
const db = prisma as any;
let server: ChildProcess | null = null;
const serverLog: string[] = [];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const tok = (userId: number) => jwt.sign({ userId }, SECRET, { expiresIn: '2h' });

async function api(method: string, p: string, uid: number | null, body?: unknown) {
  const res = await fetch(BASE + p, {
    method,
    headers: { 'content-type': 'application/json', ...(uid ? { authorization: `Bearer ${tok(uid)}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json: any = null;
  try { json = await res.json(); } catch { json = null; }
  return { status: res.status, body: json };
}
const ok = async (r: Promise<{ status: number; body: any }>) => {
  const x = await r;
  assert.equal(x.status, 200, JSON.stringify(x.body));
  return x.body.data;
};
const denied = async (r: Promise<{ status: number; body: any }>, status = 403) => {
  const x = await r;
  assert.equal(x.status, status, JSON.stringify(x.body));
  assert.match(String(x.body?.message ?? ''), /[؀-ۿ]/, 'Arabic message');
};

const U: Record<string, number> = {};
const D: Record<string, number> = {};
let balances: Record<number, number> = {};

async function wipe() {
  const tables: { tablename: string }[] = await db.$queryRawUnsafe(
    `SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`,
  );
  await db.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} RESTART IDENTITY CASCADE`);
}

async function seed() {
  let n = 0;
  const mk = async (key: string, extra: any = {}) => {
    n++;
    const u = await db.user.create({ data: { name: key, displayId: 100_000 + n, coinsBalance: 50_000, ...extra } });
    U[key] = u.id;
    D[key] = u.displayId;
  };
  await mk('owner', { isAdmin: true, isSuperAdmin: true });
  for (const k of ['m', 'sa', 'adminB', 'adminC', 'x', 'y', 'p', 'agent', 'agent2', 'm2']) {
    await mk(k, k === 'x' ? { vipLevel: 3, totalRecharge: 1_500_000, level: 4, xp: 1000 } : {});
  }
  for (const [id, type] of [['frame1', 'FRAME'], ['bubble1', 'CHAT_BUBBLE'], ['entry1', 'ENTRANCE_BANNER'], ['badge1', 'BADGE']]) {
    await db.item.create({ data: { id, name: id, description: id, type, assetUrl: `/${id}.png`, priceCoins: 1000 } });
  }
  const rows = await db.user.findMany({ select: { id: true, coinsBalance: true } });
  balances = Object.fromEntries(rows.map((r: any) => [r.id, r.coinsBalance]));
}

function startServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    server = spawn(process.execPath, [path.resolve(__dirname, '../../dist/index.js')], {
      cwd: path.resolve(__dirname, '../..'),
      env: { ...process.env, DATABASE_URL: DB, JWT_SECRET: SECRET, JWT_REFRESH_SECRET: REFRESH, PORT: String(PORT), REDIS_URL: '', NODE_ENV: 'test' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const t = setTimeout(() => reject(new Error('server did not start:\n' + serverLog.join(''))), 60_000);
    server.stdout!.on('data', (d: Buffer) => {
      serverLog.push(d.toString());
      if (d.toString().includes('running on port')) { clearTimeout(t); resolve(); }
    });
    server.stderr!.on('data', (d: Buffer) => serverLog.push(d.toString()));
    server.on('exit', (code) => reject(new Error(`server exited ${code}\n` + serverLog.join(''))));
  });
}

function sock(uid: number): Promise<any> {
  return new Promise((resolve, reject) => {
    const s = ioc(`http://127.0.0.1:${PORT}`, { auth: { token: tok(uid) }, transports: ['websocket'], forceNew: true });
    s.events = [] as any[];
    s.onAny((ev: string, data: any) => s.events.push({ ev, data }));
    s.on('connect', () => resolve(s));
    s.on('connect_error', reject);
  });
}

describe('نظام الإدارة والصلاحيات (e2e)', { skip: SKIP ? 'E2E_DATABASE_URL (localhost) not set' : false }, () => {
  const sockets: any[] = [];
  before(async () => {
    await wipe();
    await seed();
    await startServer();
  });
  after(async () => {
    sockets.forEach((s) => s.close());
    server?.kill();
    await prisma?.$disconnect();
  });

  let saRole = 0;
  let adminBRole = 0;
  let vipGrantId = 0;
  let agencyId = 0;

  test('a regular user sees no admin system; the dashboard appoints a Manager', async () => {
    const plain = await ok(api('GET', '/staff/me', U.x));
    assert.equal(plain.role, null);
    assert.deepEqual(plain.panels, { manager: false, superAdmin: false, admin: false, ban: false });
    await denied(api('POST', '/admin-dashboard/staff/managers', U.m, { displayId: D.m, days: 30 }));
    const m = await ok(api('POST', '/admin-dashboard/staff/managers', U.owner, { displayId: D.m, days: 30 }));
    assert.equal(m.role, 'MANAGER');
    const me = await ok(api('GET', '/staff/me', U.m));
    assert.equal(me.panels.manager, true);
    assert.equal(me.panels.ban, true, 'a Manager holds the ban system');
    // Separate from the platform's own admin: no dashboard / coin access.
    await denied(api('GET', '/admin-dashboard/staff', U.m));
    assert.equal((await api('POST', `/admin/users/${U.x}/coins/add`, U.m, { amount: 10 })).status, 403);
  });

  test('dashboard sets the grantable pool and the Admin role rewards', async () => {
    await ok(api('PUT', '/admin-dashboard/staff/pool', U.owner, { itemIds: ['frame1', 'bubble1', 'entry1'] }));
    await ok(api('PUT', '/admin-dashboard/staff/role-rewards', U.owner, { ADMIN: ['badge1'] }));
    const pool = await ok(api('GET', '/staff/items/pool', U.m));
    assert.deepEqual(pool.map((i: any) => i.id).sort(), ['bubble1', 'entry1', 'frame1']);
  });

  test('Manager appoints a Super Admin; the Super Admin appoints an Admin who gets the admin reward', async () => {
    const sa = await ok(api('POST', '/staff/members', U.m, { displayId: D.sa, role: 'SUPER_ADMIN', allowedItemIds: ['frame1'] }));
    saRole = sa.id;
    assert.equal(Math.round((new Date(sa.expiresAt).getTime() - Date.now()) / DAY), 30, 'base term is a month');
    const saMe = await ok(api('GET', '/staff/me', U.sa));
    assert.equal(saMe.panels.superAdmin, true);
    assert.equal(saMe.panels.ban, false);
    assert.ok(saMe.permissions.includes('manage_admins'));
    await denied(api('POST', '/staff/members', U.sa, { userId: U.y, role: 'SUPER_ADMIN' }));
    await denied(api('POST', '/staff/members', U.sa, { userId: U.adminB, role: 'ADMIN', days: 31 }), 400);
    const b = await ok(api('POST', '/staff/members', U.sa, { userId: U.adminB, role: 'ADMIN', days: 10 }));
    adminBRole = b.id;
    assert.equal(b.parentUserId, U.sa);
    const reward = await db.userItem.findUnique({ where: { userId_itemId: { userId: U.adminB, itemId: 'badge1' } } });
    assert.ok(reward, 'Admin Badge granted with the role');
    assert.equal(new Date(reward.expiresAt).getTime(), new Date(b.expiresAt).getTime());
    await denied(api('POST', '/staff/members', U.m, { userId: U.adminB, role: 'ADMIN' }), 409);
    await ok(api('POST', '/staff/members', U.m, { userId: U.adminC, role: 'ADMIN' }));
  });

  test('VIP 3 → granted VIP 5 → back to VIP 3; refusals and the product list are enforced', async () => {
    const g = await ok(api('POST', '/staff/grants/vip', U.sa, { userId: U.x, level: 5 }));
    vipGrantId = g.id;
    assert.equal((await db.user.findUnique({ where: { id: U.x } })).vipLevel, 5);
    await ok(api('POST', `/staff/grants/${g.id}/revoke`, U.sa));
    assert.equal((await db.user.findUnique({ where: { id: U.x } })).vipLevel, 3, 'original VIP restored');
    await denied(api('POST', '/staff/grants/vip', U.sa, { userId: U.x, level: 3 }), 400);
    await denied(api('POST', '/staff/grants/vip', U.sa, { userId: U.x, level: 6 }), 400);
    await denied(api('POST', '/staff/grants/vip', U.adminB, { userId: U.x, level: 5 }));
    await denied(api('POST', '/staff/grants/vip', U.sa, { userId: U.sa, level: 5 }));
    const lv = await ok(api('POST', '/staff/grants/level', U.sa, { userId: U.x, level: 15 }));
    assert.equal((await db.user.findUnique({ where: { id: U.x } })).level, 15);
    const v2 = await ok(api('POST', '/staff/grants/vip', U.sa, { userId: U.x, level: 5 }));
    vipGrantId = v2.id;
    assert.ok(lv.id && v2.id);
    // Products: only what the Manager selected for him.
    const item = await ok(api('POST', '/staff/grants/item', U.sa, { userId: U.y, itemId: 'frame1' }));
    const owned = await db.userItem.findUnique({ where: { userId_itemId: { userId: U.y, itemId: 'frame1' } } });
    assert.equal(new Date(owned.expiresAt).getTime(), new Date(item.expiresAt).getTime());
    assert.equal(Math.round((new Date(item.expiresAt).getTime() - Date.now()) / DAY), 7);
    await denied(api('POST', '/staff/grants/item', U.sa, { userId: U.y, itemId: 'bubble1' }));
    await ok(api('POST', '/staff/grants/item', U.m, { userId: U.y, itemId: 'bubble1' }));
    const grantable = await ok(api('GET', '/staff/items/grantable', U.sa));
    assert.deepEqual(grantable.map((i: any) => i.id), ['frame1']);
  });

  test('hosting agencies follow the scope tree', async () => {
    const a = await ok(api('POST', '/staff/agencies', U.adminB, { ownerUserId: U.agent, agencyName: 'وكالة النجوم' }));
    agencyId = a.id;
    assert.equal(a.type, 'HOSTING');
    const saList = await ok(api('GET', '/staff/agencies', U.sa));
    assert.ok(saList.some((x: any) => x.id === agencyId), 'SA sees his Admin\'s agency');
    const mList = await ok(api('GET', '/staff/agencies', U.m));
    assert.ok(mList.some((x: any) => x.id === agencyId), 'Manager sees his subtree');
    await denied(api('GET', `/staff/agencies/${agencyId}`, U.adminC));
    const detail = await ok(api('GET', `/staff/agencies/${agencyId}`, U.adminB));
    assert.equal(detail.hosts.length, 1);
    await ok(api('POST', `/staff/agencies/${agencyId}/followers`, U.m, { staffUserId: U.adminC }));
    await ok(api('GET', `/staff/agencies/${agencyId}`, U.adminC));
  });

  test('ban system: granted, used, refused against staff, withdrawn', async () => {
    const p = await sock(U.p);
    sockets.push(p);
    await denied(api('POST', '/staff/bans', U.p, { userId: U.y, duration: '1d', reason: 'x' }));
    await ok(api('POST', '/staff/ban-holders', U.m, { userId: U.p, days: 7 }));
    const me = await ok(api('GET', '/staff/me', U.p));
    assert.deepEqual(me.panels, { manager: false, superAdmin: false, admin: false, ban: true });
    await sleep(300);
    assert.ok(p.events.some((e: any) => e.ev === 'staff_access_changed'));
    await denied(api('POST', '/staff/bans', U.p, { userId: U.y, duration: '1d', reason: ' ' }), 400);
    await denied(api('POST', '/staff/bans', U.p, { userId: U.y, duration: '2d', reason: 'مخالفة' }), 400);
    await denied(api('POST', '/staff/bans', U.p, { userId: U.sa, duration: '1d', reason: 'مخالفة' }));
    await denied(api('POST', '/staff/bans', U.p, { userId: U.owner, duration: '1d', reason: 'مخالفة' }));
    const ban = await ok(api('POST', '/staff/bans', U.p, { userId: U.y, duration: '7d', reason: 'مخالفة القوانين' }));
    assert.equal(ban.duration, '7d');
    const blocked = await api('GET', '/staff/me', U.y);
    assert.equal(blocked.status, 403);
    assert.equal(blocked.body.code, 'BANNED');
    await ok(api('POST', `/staff/bans/${U.y}/unban`, U.p));
    await ok(api('GET', '/staff/me', U.y));
    await ok(api('DELETE', `/staff/ban-holders/${U.p}`, U.m));
    assert.equal((await ok(api('GET', '/staff/me', U.p))).panels.ban, false);
    await denied(api('POST', '/staff/bans', U.p, { userId: U.y, duration: '1d', reason: 'مخالفة' }));
  });

  test('withdrawing the Super Admin: role, permissions and API gone; his Admin moves to the Manager', async () => {
    const s = await sock(U.sa);
    sockets.push(s);
    await ok(api('POST', `/staff/members/${saRole}/revoke`, U.m, { reason: 'إنهاء' }));
    await sleep(300);
    assert.ok(s.events.some((e: any) => e.ev === 'staff_access_changed'));
    const me = await ok(api('GET', '/staff/me', U.sa));
    assert.equal(me.role, null);
    assert.equal(me.panels.superAdmin, false);
    await denied(api('POST', '/staff/grants/vip', U.sa, { userId: U.y, level: 2 }));
    await denied(api('GET', '/staff/members', U.sa));
    const b = await db.staffRole.findUnique({ where: { id: adminBRole } });
    assert.equal(b.parentUserId, U.m);
    assert.equal(b.status, 'ACTIVE');
    // Renewal keeps history.
    const renewed = await ok(api('POST', `/staff/members/${saRole}/renew`, U.m, { days: 15 }));
    assert.notEqual(renewed.id, saRole);
    assert.equal((await db.staffRole.findUnique({ where: { id: saRole } })).status, 'REVOKED');
    assert.equal((await ok(api('GET', '/staff/me', U.sa))).role, 'SUPER_ADMIN');
  });

  test('expiry: access ends at once, the job retires role, reward and grants and restores VIP', async () => {
    const past = new Date(Date.now() - 1000);
    await db.staffRole.update({ where: { id: adminBRole }, data: { expiresAt: past } });
    await db.temporaryEntitlement.update({ where: { id: vipGrantId }, data: { expiresAt: past } });
    const me = await ok(api('GET', '/staff/me', U.adminB));
    assert.equal(me.role, null, 'live check before the job runs');
    await denied(api('POST', '/staff/agencies', U.adminB, { ownerUserId: U.agent2, agencyName: 'y' }));
    let role: any = null;
    for (let i = 0; i < 80; i++) {
      role = await db.staffRole.findUnique({ where: { id: adminBRole } });
      if (role.status === 'EXPIRED') break;
      await sleep(1000);
    }
    assert.equal(role.status, 'EXPIRED');
    assert.equal(await db.userItem.findUnique({ where: { userId_itemId: { userId: U.adminB, itemId: 'badge1' } } }), null, 'Admin Badge withdrawn');
    const x = await db.user.findUnique({ where: { id: U.x } });
    assert.equal(x.vipLevel, 3, 'VIP back to the original after the 7-day grant ends');
    assert.equal(x.level, 15, 'the Level grant is still running');
    const logs = await db.adminAuditLog.findMany({ where: { action: { in: ['STAFF_EXPIRED', 'STAFF_GRANT_EXPIRED'] } } });
    assert.ok(logs.length >= 2);
    assert.ok(logs.every((l: any) => l.adminId === 0));
  });

  test('audit log reads by scope and nothing moved a coin', async () => {
    const mine = await ok(api('GET', '/staff/audit', U.m));
    const actions = new Set(mine.rows.map((r: any) => r.action));
    for (const a of ['STAFF_APPOINT', 'STAFF_REVOKE', 'STAFF_GRANT_VIP', 'STAFF_AGENCY_CREATE', 'STAFF_BAN']) assert.ok(actions.has(a), a);
    assert.ok(mine.rows.some((r: any) => r.actor?.id === U.sa), 'rows carry the actor\'s name');
    const c = await ok(api('GET', '/staff/audit', U.adminC));
    assert.ok(c.rows.every((r: any) => r.adminId === U.adminC));
    const all = await ok(api('GET', '/admin-dashboard/staff/audit', U.owner));
    assert.ok(all.total >= mine.total);
    const rows = await db.user.findMany({ select: { id: true, coinsBalance: true } });
    for (const r of rows) assert.equal(r.coinsBalance, balances[r.id], `coins of user ${r.id} unchanged`);
    assert.equal(await db.chargingAgency.count({ where: { type: 'CHARGING' } }), 0);
  });
});
