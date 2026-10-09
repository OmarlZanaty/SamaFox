import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';
import { refreshTokenKey } from '../refreshLimit';
import { trustProxySetting } from '../../utils/trustProxy';
import { clientIp } from '../deviceBan.middleware';

test('a refresh is limited per token, not per shared carrier IP', () => {
  const a = refreshTokenKey({ body: { refreshToken: 'token-a' }, ip: '41.33.1.1' });
  const b = refreshTokenKey({ body: { refreshToken: 'token-b' }, ip: '41.33.1.1' });
  assert.notEqual(a, b, 'two phones behind one CGNAT address get their own budgets');
  assert.equal(a, refreshTokenKey({ body: { refreshToken: 'token-a' }, ip: '10.0.0.9' }));
  assert.ok(!a.includes('token-a'), 'the token itself is never used as a key');
  assert.equal(refreshTokenKey({ body: {}, ip: '41.33.1.1' }), 'refresh-ip:41.33.1.1');
});

test('trust proxy: only loopback (Caddy) may name the client', () => {
  const app = express();
  app.set('trust proxy', trustProxySetting({}));
  const trust = app.get('trust proxy fn') as (addr: string, i: number) => boolean;
  assert.equal(trust('127.0.0.1', 0), true);
  assert.equal(trust('::1', 0), true);
  assert.equal(trust('203.0.113.9', 0), false, 'a direct caller on :3000 is not a proxy');
  assert.equal(trustProxySetting({ TRUST_PROXY_HOPS: '2' }), 2);
});

test('behind Caddy, req.ip and clientIp are the phone, not 127.0.0.1', async () => {
  const app = express();
  app.set('trust proxy', trustProxySetting({}));
  app.get('/ip', (req, res) => {
    res.json({ ip: req.ip, clientIp: clientIp(req) });
  });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  const port = (server.address() as { port: number }).port;
  const body = await new Promise<string>((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port, path: '/ip', headers: { 'X-Forwarded-For': '41.33.1.1' } }, (res) => {
        let s = '';
        res.on('data', (c) => (s += c));
        res.on('end', () => resolve(s));
      })
      .on('error', reject);
  });
  server.close();
  assert.deepEqual(JSON.parse(body), { ip: '41.33.1.1', clientIp: '41.33.1.1' });
});
