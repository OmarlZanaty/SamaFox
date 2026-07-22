/* eslint-disable */
const API = {
  list: () => fetch('/api/v2/admin/gifts', { credentials: 'include' }).then(r => r.json()),
  get: (id) => fetch('/api/v2/admin/gifts/' + id, { credentials: 'include' }).then(r => r.json()),
  create: (body) => fetch('/api/v2/admin/gifts', { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(r => r.json()),
  update: (id, body) => fetch('/api/v2/admin/gifts/' + id, { method: 'PATCH', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(r => r.json()),
  remove: (id) => fetch('/api/v2/admin/gifts/' + id, { method: 'DELETE', credentials: 'include' }).then(r => r.json()),
  templates: () => fetch('/api/v2/admin/gifts/templates', { credentials: 'include' }).then(r => r.json()),
  template: (key) => fetch('/api/v2/admin/gifts/templates/' + key, { credentials: 'include' }).then(r => r.json()),
  preview: (id) => '/api/v2/admin/gifts/' + id + '/preview',
  exportAll: () => '/api/v2/admin/gifts/export',
  audit: () => fetch('/api/v2/admin/gifts/audit-log', { credentials: 'include' }).then(r => r.json()),
  bulkImport: (body) => fetch('/api/v2/admin/gifts/bulk-import', { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(r => r.json()),
  uploadVideo: (file) => { const fd = new FormData(); fd.append('file', file); return fetch('/api/v2/admin/gifts/upload-video', { method: 'POST', credentials: 'include', body: fd }).then(r => r.json()); },
  uploadIcon: (file) => { const fd = new FormData(); fd.append('file', file); return fetch('/api/v2/admin/gifts/upload-icon', { method: 'POST', credentials: 'include', body: fd }).then(r => r.json()); },
  me: () => fetch('/api/v1/admin-dashboard-auth/status', { credentials: 'include' }).then(r => r.json()).catch(() => ({ success: false })),
};

const state = {
  gifts: [],
  filtered: [],
  currentId: null,
  draft: null,
  saving: false,
  filters: { q: '', tier: '', format: '', active: '' },
};

function toast(msg, kind = 'ok') {
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.textContent = msg;
  document.getElementById('toasts').appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

async function loadList() {
  try {
    const res = await API.list();
    if (!res.success) {
      toast(res.message || 'Failed to load', 'err');
      return;
    }
    state.gifts = res.gifts || [];
    applyFilters();
  } catch (err) {
    toast('Network error loading gifts', 'err');
  }
}

function applyFilters() {
  const { q, tier, format, active } = state.filters;
  state.filtered = state.gifts.filter((g) => {
    if (q && !((g.name || '').toLowerCase().includes(q.toLowerCase()) || (g.nameAr || '').includes(q))) return false;
    if (tier && g.tier !== tier) return false;
    if (format && g.format !== format) return false;
    if (active === 'true' && !g.isActive) return false;
    if (active === 'false' && g.isActive) return false;
    return true;
  });
  renderList();
}

function renderList() {
  const root = document.getElementById('gift-list');
  if (state.filtered.length === 0) {
    root.innerHTML = '<div class="muted" style="padding:20px;text-align:center;">No gifts match.</div>';
    return;
  }
  root.innerHTML = state.filtered.map((g) => `
    <div class="gift-row ${g.id === state.currentId ? 'active' : ''} ${g.isActive ? '' : 'inactive'}" data-id="${g.id}">
      <div class="icon">${g.iconUrl ? `<img src="${escapeHtml(g.iconUrl)}" onerror="this.style.display='none'">` : ''}</div>
      <div class="meta">
        <div class="name">${escapeHtml(g.name)}</div>
        <div class="sub">
          <span class="tier-pill tier-${g.tier}">${g.tier}</span>
          <span>${g.format}</span>
          <span>${g.coinCost}🪙</span>
        </div>
      </div>
    </div>
  `).join('');
  root.querySelectorAll('.gift-row').forEach((row) => {
    row.addEventListener('click', () => openGift(row.dataset.id));
  });
}

async function openGift(id) {
  const res = await API.get(id);
  if (!res.success) return toast(res.message || 'Not found', 'err');
  state.currentId = id;
  state.draft = { ...res.gift };
  renderList();
  renderEditor();
}

function newGift(template) {
  state.currentId = null;
  state.draft = template ? {
    name: template.name + ' (copy)',
    nameAr: template.nameAr,
    iconUrl: '',
    format: 'SVG_CSS',
    animationHtml: template.html,
    animationUrl: '',
    videoHasAlpha: false,
    fireworksEnabled: false,
    fireworksColors: ['#FFD700', '#FF6B9D', '#FFFFFF'],
    coinCost: template.coinCost,
    tier: template.tier,
    animationMs: template.animationMs,
    isComboEligible: true,
    broadcastGlobal: false,
    isActive: true,
    sortOrder: 0,
    category: template.category,
  } : {
    name: '',
    nameAr: '',
    iconUrl: '',
    format: 'SVG_CSS',
    animationHtml: '',
    animationUrl: '',
    videoHasAlpha: false,
    fireworksEnabled: false,
    fireworksColors: ['#FFD700', '#FF6B9D', '#FFFFFF'],
    coinCost: 10,
    tier: 'SMALL',
    animationMs: 2500,
    isComboEligible: true,
    broadcastGlobal: false,
    isActive: true,
    sortOrder: 0,
    category: 'love',
  };
  renderList();
  renderEditor();
}

let previewDebounce = null;
function debouncePreview() {
  clearTimeout(previewDebounce);
  previewDebounce = setTimeout(refreshPreview, 500);
}

function bytes(s) { return new Blob([s || '']).size; }

function validateDraft(d) {
  const issues = [];
  if (!d.name) issues.push({ level: 'err', msg: 'Name is required' });
  if (!d.iconUrl) issues.push({ level: 'warn', msg: 'iconUrl is missing — picker will show a placeholder' });
  if (d.format === 'SVG_CSS') {
    if (!d.animationHtml) issues.push({ level: 'err', msg: 'animationHtml is required for SVG_CSS' });
    else {
      const b = bytes(d.animationHtml);
      if (b > 200 * 1024) issues.push({ level: 'err', msg: `animationHtml is ${(b/1024).toFixed(1)}KB (>200KB limit)` });
      if (/<script\b/i.test(d.animationHtml)) issues.push({ level: 'err', msg: '<script> tags are not allowed' });
      if (/\son\w+\s*=/i.test(d.animationHtml)) issues.push({ level: 'err', msg: 'on* event handlers are not allowed' });
      if (!/<svg\b/i.test(d.animationHtml)) issues.push({ level: 'err', msg: 'Animation must contain an <svg> element' });
    }
  } else if (d.format === 'VIDEO') {
    if (!d.animationUrl) issues.push({ level: 'err', msg: 'animationUrl is required for VIDEO' });
    if (d.tier !== 'LEGENDARY') issues.push({ level: 'warn', msg: 'VIDEO format is only intended for LEGENDARY tier' });
  }
  if (d.tier === 'LEGENDARY' && d.format !== 'VIDEO') {
    issues.push({ level: 'err', msg: 'LEGENDARY tier requires VIDEO format' });
  }
  return issues;
}

function refreshPreview() {
  const d = state.draft;
  if (!d) return;
  const root = document.getElementById('preview-root');
  if (!root) return;
  if (d.format === 'SVG_CSS') {
    if (d.animationHtml) {
      const iframe = document.createElement('iframe');
      iframe.sandbox = 'allow-same-origin';
      iframe.srcdoc = d.animationHtml;
      root.innerHTML = '';
      root.appendChild(iframe);
    } else {
      root.innerHTML = '<div class="placeholder">Paste HTML to see preview…</div>';
    }
  } else if (d.format === 'VIDEO') {
    if (d.animationUrl) {
      root.innerHTML = `<div class="preview-video" style="width:100%;height:100%"><video src="${escapeHtml(d.animationUrl)}" autoplay muted loop></video></div>`;
    } else {
      root.innerHTML = '<div class="placeholder">Upload a video to preview…</div>';
    }
  }
  const validation = document.getElementById('validation');
  const issues = validateDraft(d);
  if (issues.length === 0) {
    validation.innerHTML = '<div class="validation ok">✓ Valid — ready to save</div>';
  } else {
    validation.innerHTML = issues.map((i) => `<div class="validation ${i.level}">${i.level === 'err' ? '✗' : '⚠'} ${escapeHtml(i.msg)}</div>`).join('');
  }
}

function renderEditor() {
  const root = document.getElementById('editor');
  if (!state.draft) { root.classList.add('empty'); return; }
  root.classList.remove('empty');
  const d = state.draft;
  const isEdit = !!state.currentId;
  root.innerHTML = `
    <div class="topbar">
      <h3>${isEdit ? 'Edit Gift' : 'New Gift'}${d.name ? `: ${escapeHtml(d.name)}` : ''} <span class="tier-pill tier-${d.tier}">${d.tier}</span></h3>
      <div class="actions-row" style="margin:0">
        <button class="ghost" id="btn-cancel">Cancel</button>
        ${isEdit ? `<button class="danger" id="btn-delete">Deactivate</button>` : ''}
        <button class="primary" id="btn-save">${isEdit ? 'Save changes' : 'Create gift'}</button>
      </div>
    </div>
    <div class="panes">
      <div class="pane pane-divider">
        <div class="row2">
          <div class="field"><label>Name (EN)</label><input id="f-name" type="text" value="${escapeHtml(d.name)}"></div>
          <div class="field"><label>Name (AR)</label><input id="f-nameAr" type="text" value="${escapeHtml(d.nameAr || '')}" dir="rtl"></div>
        </div>
        <div class="row3">
          <div class="field"><label>Tier</label>
            <select id="f-tier">${['SMALL','MEDIUM','LARGE','LEGENDARY'].map((t) => `<option ${d.tier===t?'selected':''}>${t}</option>`).join('')}</select>
          </div>
          <div class="field"><label>Format</label>
            <select id="f-format">${['SVG_CSS','VIDEO'].map((t) => `<option ${d.format===t?'selected':''}>${t}</option>`).join('')}</select>
          </div>
          <div class="field"><label>Category (tab in the app)</label>
            <select id="f-category">${[
              ['love','العلاقة'], ['luxury','خاص'], ['lucky','محظوظ'],
              ['magic','ماجيك'], ['flag','علم'], ['bag','كيس'],
            ].map(([v,label]) => `<option value="${v}" ${d.category===v?'selected':''}>${v} — ${label}</option>`).join('')}</select>
          </div>
        </div>
        <div class="row3">
          <div class="field"><label>Cost (coins)</label><input id="f-coinCost" type="number" min="0" value="${d.coinCost}"></div>
          <div class="field"><label>Duration (ms)</label><input id="f-animationMs" type="number" min="500" step="100" value="${d.animationMs}"></div>
          <div class="field"><label>Sort order</label><input id="f-sortOrder" type="number" value="${d.sortOrder}"></div>
        </div>
        <div class="field">
          <label>Icon URL</label>
          <div class="row2">
            <input id="f-iconUrl" type="text" value="${escapeHtml(d.iconUrl || '')}" placeholder="/assets/icons/...">
            <input id="f-iconUpload" type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml">
          </div>
        </div>
        <div class="row3">
          <label class="toggle"><input type="checkbox" id="f-isActive" ${d.isActive?'checked':''}> Active</label>
          <label class="toggle"><input type="checkbox" id="f-isComboEligible" ${d.isComboEligible?'checked':''}> Combo eligible</label>
          <label class="toggle"><input type="checkbox" id="f-broadcastGlobal" ${d.broadcastGlobal?'checked':''}> Broadcast globally</label>
        </div>

        ${d.format === 'SVG_CSS' ? `
          <div class="field">
            <label>Animation HTML <span class="muted" id="size-indicator"></span></label>
            <textarea id="f-animationHtml" class="code-area" spellcheck="false">${escapeHtml(d.animationHtml || '')}</textarea>
          </div>
        ` : `
          <div class="field">
            <label>Video upload (MP4 / WebM)</label>
            <input id="f-videoUpload" type="file" accept="video/mp4,video/webm,video/quicktime">
            <input id="f-animationUrl" type="text" value="${escapeHtml(d.animationUrl || '')}" placeholder="/assets/videos/..." style="margin-top:8px">
          </div>
          <div class="row3">
            <label class="toggle"><input type="checkbox" id="f-videoHasAlpha" ${d.videoHasAlpha?'checked':''}> Alpha channel</label>
            <label class="toggle"><input type="checkbox" id="f-fireworksEnabled" ${d.fireworksEnabled?'checked':''}> Fireworks</label>
            <div></div>
          </div>
          <div class="field" id="fireworks-colors-field" style="${d.fireworksEnabled?'':'display:none'}">
            <label>Fireworks colors (5 swatches)</label>
            <input id="f-fireworksColors" type="text" value="${escapeHtml((d.fireworksColors||[]).join(','))}" placeholder="#FFD700,#FF6B9D,#FFFFFF">
          </div>
        `}
      </div>
      <div class="pane">
        <label class="muted" style="font-size:11px;text-transform:uppercase;letter-spacing:.5px">Live preview</label>
        <div class="preview"><div id="preview-root"><div class="placeholder">Preview will render here…</div></div></div>
        <div id="validation" style="margin-top:10px"></div>
      </div>
    </div>
  `;
  bindFieldEvents();
  refreshPreview();
  updateSizeIndicator();
}

function updateSizeIndicator() {
  const ind = document.getElementById('size-indicator');
  if (!ind || !state.draft) return;
  const b = bytes(state.draft.animationHtml || '');
  const pct = (b / (200 * 1024)) * 100;
  ind.textContent = ` · ${(b/1024).toFixed(1)}KB (${pct.toFixed(0)}% of 200KB limit)`;
  ind.style.color = pct > 100 ? 'var(--err)' : pct > 80 ? 'var(--warn)' : 'var(--muted)';
}

function bindFieldEvents() {
  const d = state.draft;
  const bind = (id, key, transform = (v) => v) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener(el.type === 'checkbox' ? 'change' : 'input', () => {
      d[key] = el.type === 'checkbox' ? el.checked : transform(el.value);
      if (key === 'animationHtml') { updateSizeIndicator(); }
      debouncePreview();
      if (key === 'format' || key === 'tier' || key === 'fireworksEnabled') {
        renderEditor();
      }
    });
  };
  bind('f-name', 'name');
  bind('f-nameAr', 'nameAr');
  bind('f-iconUrl', 'iconUrl');
  bind('f-tier', 'tier');
  bind('f-format', 'format');
  bind('f-category', 'category');
  bind('f-coinCost', 'coinCost', Number);
  bind('f-animationMs', 'animationMs', Number);
  bind('f-sortOrder', 'sortOrder', Number);
  bind('f-isActive', 'isActive');
  bind('f-isComboEligible', 'isComboEligible');
  bind('f-broadcastGlobal', 'broadcastGlobal');
  bind('f-animationHtml', 'animationHtml');
  bind('f-animationUrl', 'animationUrl');
  bind('f-videoHasAlpha', 'videoHasAlpha');
  bind('f-fireworksEnabled', 'fireworksEnabled');
  const fcEl = document.getElementById('f-fireworksColors');
  if (fcEl) fcEl.addEventListener('input', () => { d.fireworksColors = fcEl.value.split(',').map((s) => s.trim()).filter(Boolean); });

  document.getElementById('btn-cancel').addEventListener('click', () => { state.draft = null; state.currentId = null; renderList(); renderEditor(); });
  const delBtn = document.getElementById('btn-delete');
  if (delBtn) delBtn.addEventListener('click', deactivateGift);
  document.getElementById('btn-save').addEventListener('click', saveDraft);

  const iconUpload = document.getElementById('f-iconUpload');
  if (iconUpload) iconUpload.addEventListener('change', async (e) => {
    const file = e.target.files[0]; if (!file) return;
    const res = await API.uploadIcon(file);
    if (res.success) { d.iconUrl = res.url; document.getElementById('f-iconUrl').value = res.url; toast('Icon uploaded'); }
    else toast(res.message || 'Icon upload failed', 'err');
  });
  const videoUpload = document.getElementById('f-videoUpload');
  if (videoUpload) videoUpload.addEventListener('change', async (e) => {
    const file = e.target.files[0]; if (!file) return;
    toast('Uploading video, validating with ffprobe…');
    const res = await API.uploadVideo(file);
    if (res.success) {
      d.animationUrl = res.url;
      d.videoHasAlpha = res.hasAlpha;
      d.animationMs = Math.round(res.duration * 1000);
      document.getElementById('f-animationUrl').value = res.url;
      document.getElementById('f-animationMs').value = d.animationMs;
      const ah = document.getElementById('f-videoHasAlpha'); if (ah) ah.checked = res.hasAlpha;
      refreshPreview();
      toast(`Video OK — ${res.resolution} @ ${res.framerate}fps, ${(res.fileSize/1024/1024).toFixed(1)}MB`);
    } else {
      toast(res.message || 'Video upload failed', 'err');
    }
  });
}

async function saveDraft() {
  if (state.saving || !state.draft) return;
  const issues = validateDraft(state.draft);
  if (issues.some((i) => i.level === 'err')) { toast('Fix validation errors first', 'err'); return; }
  state.saving = true;
  try {
    const res = state.currentId ? await API.update(state.currentId, state.draft) : await API.create(state.draft);
    if (res.success) {
      toast(state.currentId ? 'Gift updated' : 'Gift created');
      await loadList();
      if (res.gift) openGift(res.gift.id);
    } else toast(res.message || 'Save failed', 'err');
  } finally { state.saving = false; }
}

async function deactivateGift() {
  if (!state.currentId) return;
  if (!confirm('Deactivate this gift? It will be hidden from the picker, existing transactions remain valid.')) return;
  const res = await API.remove(state.currentId);
  if (res.success) { toast('Deactivated'); state.draft = null; state.currentId = null; await loadList(); renderEditor(); }
  else toast(res.message || 'Failed', 'err');
}

async function openTemplatesModal() {
  const res = await API.templates();
  if (!res.success) return toast('Failed to load templates', 'err');
  const root = document.getElementById('modal-root');
  root.innerHTML = `
    <div class="modal-mask">
      <div class="modal">
        <h3>Pick a starting template</h3>
        <p class="muted">Each template meets the spec's quality bar — gradients, easing, layered particles, transparent background.</p>
        <div class="tpl-grid">
          <div class="tpl-card" data-key="__blank__">
            <div class="tpl-name">Blank</div>
            <div class="tpl-meta">Start from scratch</div>
          </div>
          ${res.templates.map((t) => `
            <div class="tpl-card" data-key="${t.key}">
              <div class="tpl-name">${escapeHtml(t.name)} <span class="tier-pill tier-${t.tier}">${t.tier}</span></div>
              <div class="tpl-meta">${escapeHtml(t.nameAr)} · ${t.coinCost}🪙 · ${t.animationMs}ms · ${(t.htmlSize/1024).toFixed(1)}KB</div>
            </div>
          `).join('')}
        </div>
        <div style="display:flex;justify-content:flex-end"><button class="ghost" id="modal-close">Cancel</button></div>
      </div>
    </div>
  `;
  root.querySelectorAll('.tpl-card').forEach((card) => {
    card.addEventListener('click', async () => {
      const key = card.dataset.key;
      root.innerHTML = '';
      if (key === '__blank__') newGift(null);
      else {
        const r = await API.template(key);
        if (r.success) newGift(r.template);
      }
    });
  });
  document.getElementById('modal-close').addEventListener('click', () => { root.innerHTML = ''; });
}

async function openAuditModal() {
  const res = await API.audit();
  if (!res.success) return toast('Failed to load audit log', 'err');
  const root = document.getElementById('modal-root');
  root.innerHTML = `
    <div class="modal-mask">
      <div class="modal" style="width:min(800px,92vw)">
        <h3>Audit log</h3>
        <table class="audit-table">
          <thead><tr><th>When</th><th>Admin</th><th>Action</th><th>Gift</th></tr></thead>
          <tbody>
            ${res.items.map((i) => `<tr><td>${new Date(i.createdAt).toLocaleString()}</td><td>#${i.adminId}</td><td>${i.action}</td><td>${i.giftId ?? '—'}</td></tr>`).join('')}
          </tbody>
        </table>
        <div style="margin-top:12px;display:flex;justify-content:flex-end"><button class="ghost" id="audit-close">Close</button></div>
      </div>
    </div>
  `;
  document.getElementById('audit-close').addEventListener('click', () => { root.innerHTML = ''; });
}

async function openBulkImportModal() {
  const root = document.getElementById('modal-root');
  root.innerHTML = `
    <div class="modal-mask">
      <div class="modal">
        <h3>Bulk import gifts</h3>
        <p class="muted">Paste a JSON document with shape <code>{"gifts": [...]}</code>. Use mode <code>upsert</code> to update existing gifts by name.</p>
        <textarea id="bulk-json" class="code-area" placeholder='{"gifts":[{"name":"...","tier":"SMALL", ...}]}'></textarea>
        <div class="row2" style="margin-top:10px">
          <label class="toggle"><input id="bulk-upsert" type="checkbox"> Upsert by name</label>
          <label class="toggle"><input id="bulk-dryrun" type="checkbox" checked> Dry-run first</label>
        </div>
        <div class="actions-row" style="justify-content:flex-end;margin-top:12px">
          <button class="ghost" id="bulk-close">Cancel</button>
          <button class="primary" id="bulk-go">Run import</button>
        </div>
        <pre id="bulk-output" style="margin-top:10px;background:#0a0820;padding:10px;border-radius:8px;font-size:11px;max-height:200px;overflow-y:auto;"></pre>
      </div>
    </div>
  `;
  document.getElementById('bulk-close').addEventListener('click', () => { root.innerHTML = ''; });
  document.getElementById('bulk-go').addEventListener('click', async () => {
    try {
      const body = JSON.parse(document.getElementById('bulk-json').value);
      body.mode = document.getElementById('bulk-upsert').checked ? 'upsert' : 'create';
      body.dryRun = document.getElementById('bulk-dryrun').checked;
      const res = await API.bulkImport(body);
      document.getElementById('bulk-output').textContent = JSON.stringify(res, null, 2);
      if (res.success) { toast('Import finished'); await loadList(); }
      else toast(res.message || 'Import failed', 'err');
    } catch (e) { toast('Invalid JSON: ' + e.message, 'err'); }
  });
}

function bindToolbar() {
  document.getElementById('btn-new').addEventListener('click', openTemplatesModal);
  document.getElementById('btn-new-empty').addEventListener('click', openTemplatesModal);
  document.getElementById('btn-export').addEventListener('click', () => { window.location.href = API.exportAll(); });
  document.getElementById('btn-audit').addEventListener('click', openAuditModal);
  document.getElementById('btn-import').addEventListener('click', openBulkImportModal);
  document.getElementById('q').addEventListener('input', (e) => { state.filters.q = e.target.value; applyFilters(); });
  document.getElementById('filter-tier').addEventListener('change', (e) => { state.filters.tier = e.target.value; applyFilters(); });
  document.getElementById('filter-format').addEventListener('change', (e) => { state.filters.format = e.target.value; applyFilters(); });
  document.getElementById('filter-active').addEventListener('change', (e) => { state.filters.active = e.target.value; applyFilters(); });
}

(async function init() {
  bindToolbar();
  const me = await API.me();
  if (me?.user) document.getElementById('me').textContent = `Admin #${me.user.id}`;
  await loadList();
})();
