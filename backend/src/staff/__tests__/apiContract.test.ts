import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function routes(file: string) {
  const source = readFileSync(resolve(__dirname, '..', file), 'utf8');
  return [...source.matchAll(/router\.(get|post|put|delete)\('([^']+)'/g)].map(m => `${m[1]!.toUpperCase()} ${m[2]}`).sort();
}
test('app surface matches Part D, with no financial, product-edit or audit-delete endpoints', () => {
  assert.deepEqual(routes('staff.routes.ts'), [
    'GET /me', 'GET /permissions/catalog', 'GET /users/lookup',
    'GET /members', 'GET /members/:roleId', 'POST /members',
    'POST /members/:roleId/extend', 'POST /members/:roleId/renew', 'POST /members/:roleId/revoke',
    'PUT /members/:roleId/permissions', 'PUT /members/:roleId/allowed-items', 'PUT /members/:roleId/reward-items',
    'GET /ban-holders', 'POST /ban-holders', 'DELETE /ban-holders/:userId',
    'GET /items/grantable', 'GET /items/pool', 'GET /config/role-rewards', 'PUT /config/role-rewards',
    'POST /grants/vip', 'POST /grants/level', 'POST /grants/item', 'GET /grants', 'POST /grants/:id/revoke',
    'GET /agencies', 'GET /agencies/:id', 'POST /agencies',
    'POST /agencies/:id/followers', 'DELETE /agencies/:id/followers/:staffUserId',
    'POST /bans', 'POST /bans/:userId/unban', 'GET /bans', 'GET /audit',
  ].sort());
});
test('dashboard surface matches Part D and mounts before the existing dashboard router', () => {
  assert.deepEqual(routes('staffDashboard.routes.ts'), [
    'GET /', 'POST /managers', 'GET /:roleId', 'POST /:roleId/extend', 'POST /:roleId/renew',
    'POST /:roleId/revoke', 'POST /:roleId/parent',
    'GET /pool', 'PUT /pool', 'GET /role-rewards', 'PUT /role-rewards', 'GET /audit', 'GET /grants', 'GET /bans',
    'GET /ban-holders',
  ].sort());
  const index = readFileSync(resolve(__dirname, '../../index.ts'), 'utf8');
  for (const prefix of ['/api/v1/admin-dashboard', '/admin-dashboard']) {
    assert.ok(index.indexOf(`app.use('${prefix}/staff',`) < index.indexOf(`app.use('${prefix}',`));
  }
  assert.match(index, /app\.use\('\/api\/v1\/staff', staffRoutes\)/);
  assert.match(index, /startExpirySweep\(\);\s*startStaffExpiryJob\(\);/);
});
