/**
 * Screenshots the عجلة الحظ preview in a given scene, by driving headless
 * Chrome over the DevTools protocol directly (no puppeteer dependency).
 *
 *   node tools/crazy-wheel-mock/shoot.js <scene> <outfile.png>
 *
 * `scene` is passed to the harness's /scene/:name endpoint first, so the
 * screen is pinned to that phase before the frame is captured.
 */
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const APP = 'http://localhost:5759';
const HARNESS = 'http://localhost:3100';
const PORT = 9222;
const WIDTH = Number(process.env.SHOT_W || 420);
const HEIGHT = Number(process.env.SHOT_H || 900);

const scene = process.argv[2] || 'betting';
const out = process.argv[3] || path.join(__dirname, `shot-${scene}.png`);

const get = (url) =>
  new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  await get(`${HARNESS}/scene/${scene}`);

  const profile = path.join(require('os').tmpdir(), `crazy-shot-${Date.now()}`);
  const chrome = spawn(CHROME, [
    '--headless=new',
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${profile}`,
    `--window-size=${WIDTH},${HEIGHT}`,
    '--hide-scrollbars',
    '--no-first-run',
    '--disable-gpu',
    APP,
  ], { stdio: 'ignore' });

  // Wait for the DevTools endpoint, then for the app to paint.
  let target = null;
  for (let i = 0; i < 40 && !target; i++) {
    await sleep(500);
    try {
      const list = JSON.parse(await get(`http://localhost:${PORT}/json/list`));
      target = list.find((t) => t.type === 'page' && t.url.startsWith(APP));
    } catch (_) { /* not up yet */ }
  }
  if (!target) throw new Error('chrome devtools target not found');

  // Flutter web has to boot, connect the socket and animate in.
  await sleep(9000);

  const WebSocket = require(path.join(__dirname, '../../backend/node_modules/ws'));
  const ws = new WebSocket(target.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((r) => ws.on('open', r));

  const send = (() => {
    let id = 0;
    const pending = new Map();
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg.result);
        pending.delete(msg.id);
      }
    });
    return (method, params = {}) =>
      new Promise((resolve) => {
        const myId = ++id;
        pending.set(myId, resolve);
        ws.send(JSON.stringify({ id: myId, method, params }));
      });
  })();

  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  fs.writeFileSync(out, Buffer.from(shot.data, 'base64'));
  console.log('wrote', out);

  ws.close();
  chrome.kill();
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
