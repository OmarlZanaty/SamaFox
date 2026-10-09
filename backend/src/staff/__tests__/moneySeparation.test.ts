import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';

test('staff source never writes money, item definitions, platform roles or charging agencies', () => {
  const root = resolve(__dirname, '..');
  for (const file of readdirSync(root).filter(f => f.endsWith('.ts'))) {
    const source = readFileSync(resolve(root, file), 'utf8');
    assert.doesNotMatch(source, /\bcoinsBalance\b|\bprice(?:Coins|Dollars)?\b|\bCHARGING\b/, file);
    assert.doesNotMatch(source, /\.item\.(?:create|update|upsert|delete)\w*\s*\(/, file);
    assert.doesNotMatch(source, /\.chargingAgency\.(?:update|upsert|delete)\w*\s*\(/, file);
    const ast = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
    function visit(node: ts.Node) {
      if (ts.isPropertyAssignment(node) && ['totalRecharge', 'xp', 'isAdmin', 'isSuperAdmin'].includes(node.name.getText(ast))) {
        // These fields may only occur in read projections, never in a write payload.
        assert.equal(node.initializer.kind, ts.SyntaxKind.TrueKeyword, `${file}: forbidden write ${node.getText(ast)}`);
        const parent = node.parent.parent;
        assert.ok(ts.isPropertyAssignment(parent) && parent.name.getText(ast) === 'select', `${file}: sensitive field outside select`);
      }
      ts.forEachChild(node, visit);
    }
    visit(ast);
  }
  const router = readFileSync(resolve(root, 'staff.routes.ts'), 'utf8');
  assert.doesNotMatch(router, /(?:coin|payment|charging|topup|economy|adminDashboard)\.(?:service|controller|routes)/i);
});

test('rules have no imports, routes use required auth and dashboard mutations require super admin', () => {
  const root = resolve(__dirname, '..');
  assert.doesNotMatch(readFileSync(resolve(root, 'staffRules.ts'), 'utf8'), /^import\s|require\(/m);
  assert.match(readFileSync(resolve(root, 'staff.routes.ts'), 'utf8'), /router\.use\(authMiddleware\)/);
  const dashboard = readFileSync(resolve(root, 'staffDashboard.routes.ts'), 'utf8');
  assert.match(dashboard, /router\.use\(authenticate, requireAdminDashboard\)/);
  for (const line of dashboard.split('\n').filter(l => /router\.(post|put|delete|patch)\(/.test(l))) assert.match(line, /requireSuperAdmin/, line);
});
