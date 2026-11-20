/* Uses the dashboard's authenticated apiFetch. */
(function () {
  'use strict';
  const labels = ['x5', 'x10', 'x100', 'x250', 'x500', 'x1000', 'x5 × x100', 'x5 × x250', 'x5 × x500', 'x5 × x1000', 'x10 × x100', 'x10 × x250', 'x10 × x500', 'x10 × x1000'];
  const base = '/admin/gifts/lucky-table';
  async function call(path, method = 'GET', body) {
    try { return await apiFetch(base + path, method, body); }
    catch (e) { showToast(e.message || 'فشل'); throw e; }
  }
  function row(r = {}) {
    const tr = document.createElement('tr');
    const input = (value, readonly) => {
      const td = tr.insertCell(), el = document.createElement('input');
      el.type = 'number'; el.min = '1'; el.step = '1'; el.value = value ?? ''; el.style.width = '95px'; el.readOnly = readonly;
      td.append(el); return el;
    };
    const value = input(r.giftValue, !!r.giftValue);
    const counts = labels.map((_, i) => input(r.thresholds?.[i], false));
    tr.insertCell().textContent = `${labels[r.tier || 0]}: ${r.counter || 0} / تجربة ${labels[r.testTier || 0]}: ${r.testCounter || 0}`;
    const actions = tr.insertCell();
    const button = (label, fn) => { const b = document.createElement('button'); b.textContent = label; b.className = 'btn btn-outline'; b.onclick = () => fn().catch(() => {}); actions.append(b); };
    button('حفظ', async () => { await call('/' + Number(value.value), 'PUT', { thresholds: counts.map(x => Number(x.value)) }); await window.lctLoad(); });
    button('تصفير', async () => window.lctReset(Number(value.value)));
    button('حذف', async () => { if (!r.giftValue) return tr.remove(); if (!confirm('حذف هذا الصف؟')) return; await call('/' + r.giftValue, 'DELETE'); await window.lctLoad(); });
    document.querySelector('#lctTable tbody').append(tr);
  }
  window.lctLoad = async () => {
    const result = await call('');
    const head = document.querySelector('#lctTable thead'); head.replaceChildren();
    const tr = document.createElement('tr');
    ['قيمة الهدية', ...labels, 'العداد الحالي / التجريبي', 'إجراءات'].forEach(label => { const th = document.createElement('th'); th.textContent = label; tr.append(th); }); head.append(tr);
    document.querySelector('#lctTable tbody').replaceChildren();
    result.data.rows.forEach(row);
  };
  window.lctAdd = () => row();
  window.lctReset = async giftValue => {
    if (giftValue !== undefined && (!Number.isInteger(giftValue) || giftValue < 1)) return showToast('اكتب قيمة هدية صحيحة');
    if (!confirm('تصفير العدادات والعودة إلى x5؟')) return;
    await call('/reset', 'POST', giftValue === undefined ? {} : { giftValue });
    await window.lctLoad();
  };
  window.lctSimulate = async () => {
    if (!document.getElementById('lctTest').checked) return;
    const n = id => Number(document.getElementById(id).value);
    const r = await call('/test', 'POST', { giftValue: n('lctValue'), quantity: n('lctQuantity'), mics: n('lctMics') });
    document.getElementById('lctResult').textContent = `مكسب وهمي: ${r.data.virtualPayout}؛ الرميات: ${r.data.throws}`;
    await window.lctLoad();
  };
})();
