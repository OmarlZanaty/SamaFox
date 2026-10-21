import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { runInNewContext } from 'node:vm';

test('economy editor shows null caps and saves cleared inputs as null', async () => {
  const elements = new Map<string, any>();
  function element(id: string) {
    if (!elements.has(id)) {
      let value = '';
      elements.set(id, {
        get value() { return value; },
        set value(v) { value = String(v); },
        style: {}, textContent: '', innerHTML: '', scrollIntoView() {},
      });
    }
    return elements.get(id);
  }
  let saved: any;
  const settings = {
    enabled: true, minBet: null, maxBet: 20_000,
    maxWinPerRound: null, dailyMaxWinPerUser: null, maxPayoutRatio: null,
    programShareBp: 3000, rtpTargetBp: 7000,
  };
  const window: any = {};
  runInNewContext(readFileSync(resolve(__dirname, '../../../public/economy-admin.js'), 'utf8'), {
    window, URLSearchParams,
    document: { getElementById: element, querySelector: element, addEventListener() {} },
    showToast() {},
    apiFetch: async (_path: string, method: string, body: unknown) => {
      if (method === 'PATCH') { saved = body; return {}; }
      return { data: { totals: {}, games: [{ game: 'greedy-cat', naturalMaxMultiplier: 45, settings }] } };
    },
  });
  await window.econLoadGames();
  window.econEdit('greedy-cat');
  assert.equal(element('econ_maxWinPerRound').value, '');
  assert.equal(element('econ_dailyMaxWinPerUser').value, '');
  assert.match(element('econNatural').textContent, /حد الجولة: بدون حد.*حد اليوم: بدون حد/);
  assert.equal(element('econ_maxBetLabel').textContent, 'أعلى رهان للخيار الواحد');
  assert.equal(element('econ_programShare').value, '30');
  // Exercise clearing previously saved caps, not just untouched empty inputs.
  element('econ_maxWinPerRound').value = 1_000_000;
  element('econ_dailyMaxWinPerUser').value = 5_000_000;
  element('econ_maxWinPerRound').value = '';
  element('econ_dailyMaxWinPerUser').value = '';
  element('econ_reason').value = 'client notes 14/10';
  await window.econSaveGame();
  assert.equal(saved.maxWinPerRound, null);
  assert.equal(saved.dailyMaxWinPerUser, null);
  assert.equal(saved.maxPayoutRatio, null);
  assert.equal(saved.programShareBp, 3000);
  assert.equal(element('econFruitBonus').style.display, 'none');
  assert.equal(saved.bonusEnabled, undefined);
});

test('fruitwheel bonus editor loads defaults and saves overrides through the audited settings path', async () => {
  const elements = new Map<string, any>();
  const element = (id: string) => {
    if (!elements.has(id)) {
      let value = '';
      elements.set(id, {
        get value() { return value; }, set value(v) { value = String(v); },
        style: {}, textContent: '', innerHTML: '', scrollIntoView() {},
      });
    }
    return elements.get(id);
  };
  const writes: any[] = [];
  const window: any = {};
  runInNewContext(readFileSync(resolve(__dirname, '../../../public/economy-admin.js'), 'utf8'), {
    window, URLSearchParams, showToast() {},
    document: { getElementById: element, querySelector: element, addEventListener() {} },
    apiFetch: async (path: string, method: string, body: unknown) => {
      if (method === 'PATCH') { writes.push({ path, body }); return {}; }
      return { data: { totals: {}, games: [{ game: 'fruitwheel', settings: { enabled: true, programShareBp: 3000 } }] } };
    },
  });
  await window.econLoadGames(); window.econEdit('fruitwheel');
  assert.equal(element('econFruitBonus').style.display, '');
  assert.equal(element('econ_bonusEnabled').value, '1');
  assert.equal(element('econ_bonusEveryRounds').value, '20');
  assert.equal(element('econ_tripleMinPool').value, '15000000');
  element('econ_bonusEnabled').value = '0';
  element('econ_bonusEveryRounds').value = '25';
  element('econ_tripleMinPool').value = '123456';
  element('econ_reason').value = 'Adjust bonus frequency';
  await window.econSaveGame();
  assert.equal(writes[0].path, '/admin-dashboard/games-economy/fruitwheel');
  assert.equal(writes[0].body.bonusEnabled, false);
  assert.equal(writes[0].body.bonusEveryRounds, 25);
  assert.equal(writes[0].body.tripleMinPool, 123456);
  assert.equal(writes[0].body.reason, 'Adjust bonus frequency');
  element('econ_bonusEveryRounds').value = '';
  element('econ_tripleMinPool').value = '';
  element('econ_reason').value = 'Restore defaults';
  await window.econSaveGame();
  assert.equal(writes[1].body.bonusEveryRounds, null);
  assert.equal(writes[1].body.tripleMinPool, null);
});
