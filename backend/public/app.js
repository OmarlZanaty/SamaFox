/* ============================================================
   SMAFOX ADMIN DASHBOARD — app.js
   ============================================================ */

"use strict";

// ---- CONSTANTS ----
const LS_API = "sf_admin_dashboard_api";
const LS_AUTH_TOKEN = "sf_admin_dashboard_token";

// ---- DOM REFS ----
const apiEl          = document.getElementById("apiBase");
const apiBaseText    = document.getElementById("apiBaseText");
const authLabel      = document.getElementById("authLabel");
const authDot        = document.getElementById("authDot");
const toast          = document.getElementById("toast");
let liveMode = true;
let liveTimer = null;
let lastUsersRows = [];
let lastTransactionsRows = [];
let lastTopupsRows = [];
let lastReportsRows = [];
let lastLeaderboardRows = [];
let changeIdUserId = null;
let changeIdTargetCell = null;

// ============================================================
// NAVIGATION
// ============================================================
const navItems   = document.querySelectorAll(".nav-item");
const sections   = document.querySelectorAll(".section");
const pageTitle  = document.getElementById("pageTitle");

const sectionTitles = {
  overview:  "نظرة عامة",
  users:     "المستخدمين",
  rooms:     "الغرف",
  agencies:  "وكالات الشحن",
  advanced:  "ميزات الأدمن",
  store:     "إدارة المتجر",
  settings:  "الإعدادات",
};

navItems.forEach(item => {
  item.addEventListener("click", e => {
    e.preventDefault();
    const sec = item.dataset.section;
    navigate(sec);
  });
});

function navigate(sec) {
  navItems.forEach(i => i.classList.toggle("active", i.dataset.section === sec));
  sections.forEach(s => s.classList.toggle("active", s.id === `section-${sec}`));
  pageTitle.textContent = sectionTitles[sec] || sec;
}

// ============================================================
// SIDEBAR TOGGLE (mobile)
// ============================================================
const sidebar       = document.getElementById("sidebar");
const sidebarToggle = document.getElementById("sidebarToggle");

sidebarToggle.addEventListener("click", () => {
  sidebar.classList.toggle("open");
});

// ============================================================
// UTILITY HELPERS
// ============================================================
let toastTimer = null;

function showToast(msg, type = "default") {
  toast.textContent = msg;
  toast.className = "toast show";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("show"), 2800);
}

window.openCreateRoomModal = function() {
  document.getElementById('createRoomModal').classList.remove('hidden');
};
window.closeCreateRoomModal = function() {
  document.getElementById('createRoomModal').classList.add('hidden');
};
window.createRoom = async function() {
  const name = document.getElementById('cr_name').value.trim();
  const ownerId = Number(document.getElementById('cr_ownerId').value);
  const maxSeats = Number(document.getElementById('cr_maxSeats').value) || 8;
  const type = document.getElementById('cr_type').value;
  if (!name || !ownerId) return showToast('اسم الغرفة ومعرف المالك مطلوبان');
  await apiFetch('/admin-dashboard/rooms', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, ownerId, maxSeats, type }),
  });
  closeCreateRoomModal();
  showToast('✓ تم إنشاء الغرفة');
  await loadRooms();
};
window.deleteRoom = async function(roomId) {
  if (!confirm('هل أنت متأكد من حذف هذه الغرفة؟')) return;
  await apiFetch(`/admin-dashboard/rooms/${roomId}`, { method: 'DELETE' });
  showToast('✓ تم حذف الغرفة');
  await loadRooms();
};

function getApiBase() {
  let base = apiEl.value.trim();
  if (base.endsWith("/")) base = base.slice(0, -1);
  // ✅ Auto-prepend http:// if missing
  if (base && !base.startsWith("http://") && !base.startsWith("https://")) {
    base = "http://" + base;
  }
  return base;
}

function saveApiBase() {
  let val = document.getElementById("apiBaseSettings").value.trim();
  if (val && !val.startsWith("http://") && !val.startsWith("https://")) {
    val = "http://" + val;
  }
  if (val.endsWith("/")) val = val.slice(0, -1);
  localStorage.setItem(LS_API, val);
  apiEl.value = val;
  apiBaseText.textContent = val || "--";
  showToast("✓ تم حفظ قاعدة الـ API");
}

function getStoredToken() {
  return localStorage.getItem(LS_AUTH_TOKEN) || "";
}

function setStoredToken(token) {
  if (token) localStorage.setItem(LS_AUTH_TOKEN, token);
  else localStorage.removeItem(LS_AUTH_TOKEN);
}

function getApiBaseCandidates() {
  const base = getApiBase();
  if (!base) return [];

  const normalized = base.replace(/\/+$/, "");
  const candidates = [normalized];

  if (normalized.endsWith("/api/v1")) {
    candidates.push(normalized.slice(0, -"/api/v1".length));
  } else {
    candidates.push(normalized + "/api/v1");
  }

  return [...new Set(candidates.filter(Boolean))];
}

async function fetchWithBaseFallback(path, opts = {}) {
  const candidates = getApiBaseCandidates();
  if (!candidates.length) throw new Error("يرجى إدخال قاعدة الـ API");

  let lastError = null;

  for (const base of candidates) {
    const token = getStoredToken();
    const authHeaders = token ? { Authorization: `Bearer ${token}` } : {};
    const res = await fetch(base + path, {
      ...opts,
      credentials: "include",
      headers: Object.assign({ Accept: "application/json" }, authHeaders, opts.headers || {}),
    });

    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }

    if (res.ok) return data;

    const apiError =
      typeof data?.error === "string"
        ? data.error
        : (data?.error && typeof data.error.message === "string" ? data.error.message : "");
    const apiMessage = typeof data?.message === "string" ? data.message : "";
    const rawText = typeof data?.raw === "string" ? data.raw.trim() : "";
    const detail = apiMessage || apiError || rawText || "";
    const msg = detail ? `HTTP ${res.status}: ${detail}` : `HTTP ${res.status}`;

    lastError = Object.assign(new Error(msg), { status: res.status });

    if (res.status !== 404) {
      throw lastError;
    }
  }

  throw lastError || new Error("تعذر الوصول إلى الـ API");
}

function fmtDate(s) {
  if (!s) return "—";
  try { return new Date(s).toISOString().replace("T", " ").slice(0, 19); }
  catch { return s; }
}

function escapeHtml(str) {
  return String(str ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function normalizeGiftImageUrl(url) {
  const value = String(url || "").trim();
  if (!value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith("/uploads/")) return value;
  return "";
}

function downloadCSV(filename, rows) {
  if (!rows || !rows.length) return showToast("لا توجد بيانات للتصدير");
  const headers = Object.keys(rows[0]);
  const csv = [headers.join(',')].concat(
    rows.map((r) => headers.map((h) => `"${String(r[h] ?? '').replaceAll('"', '""')}"`).join(',')),
  ).join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}

let confirmHandler = null;
window.openConfirmModal = function(title, text, onYes) {
  document.getElementById('confirmTitle').textContent = title || 'تأكيد الإجراء';
  document.getElementById('confirmText').textContent = text || 'هل أنت متأكد؟';
  confirmHandler = onYes;
  document.getElementById('confirmModal').classList.remove('hidden');
};
window.closeConfirmModal = function() {
  document.getElementById('confirmModal').classList.add('hidden');
  confirmHandler = null;
};
document.getElementById('confirmYesBtn')?.addEventListener('click', async () => {
  try { if (confirmHandler) await confirmHandler(); } finally { closeConfirmModal(); }
});

window.openDisplayIdModal = function(userId, btnEl) {
  changeIdUserId = Number(userId);
  changeIdTargetCell = btnEl?.closest('tr')?.querySelector('.js-display-id') || null;
  const input = document.getElementById('newDisplayIdInput');
  if (input) input.value = '';
  document.getElementById('displayIdModal')?.classList.remove('hidden');
};
window.closeDisplayIdModal = function() {
  document.getElementById('displayIdModal')?.classList.add('hidden');
  changeIdUserId = null;
  changeIdTargetCell = null;
};
window.confirmDisplayIdChange = async function() {
  const input = document.getElementById('newDisplayIdInput');
  const newDisplayId = Number(input?.value || 0);
  if (!changeIdUserId) return;
  if (!newDisplayId || newDisplayId < 10000) {
    showToast('displayId must be >= 10000');
    return;
  }
  try {
    await apiFetchAny([
      `/admin-dashboard/users/${changeIdUserId}/display-id`,
      `/admin/users/${changeIdUserId}/display-id`,
    ], 'PATCH', { newDisplayId });
    if (changeIdTargetCell) changeIdTargetCell.textContent = `#${newDisplayId}`;
    showToast('تم تحديث رقم المستخدم');
    closeDisplayIdModal();
  } catch (e) {
    showToast(e?.message || 'فشل تحديث رقم المستخدم');
  }
};



function statusBadge(s) {
  const map = {
    approved: ["badge badge-approved", "مقبولة"],
    rejected: ["badge badge-rejected", "مرفوضة"],
    pending:  ["badge badge-pending",  "قيد المراجعة"],
  };
  const [cls, label] = map[s] || map.pending;
  return `<span class="${cls}">${label}</span>`;
}

function statusText(s) {
  const map = { approved: "مقبولة", rejected: "مرفوضة", pending: "قيد المراجعة" };
  return map[s] || "قيد المراجعة";
}

// ============================================================
// API FETCH (cookie-based)
// ============================================================
async function apiFetch(path, methodOrOpts = {}, body) {
  if (typeof methodOrOpts === "string") {
    return fetchWithBaseFallback(path, {
      method: methodOrOpts,
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: body == null ? undefined : JSON.stringify(body),
    });
  }
  return fetchWithBaseFallback(path, methodOrOpts);
}

async function apiFetchAny(paths, methodOrOpts = {}, body) {
  const list = Array.isArray(paths) ? paths : [paths];
  let lastErr = null;

  for (const path of list) {
    try {
      return await apiFetch(path, methodOrOpts, body);
    } catch (e) {
      lastErr = e;
      if (e?.status !== 404) throw e;
    }
  }

  throw lastErr || new Error("تعذر الوصول إلى المسار");
}

// ============================================================
// AUTH
// ============================================================
async function doLogin(email, password) {
  try {
    const d = await fetchWithBaseFallback("/admin-dashboard-auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email, password }),
    });
    setStoredToken("");
    return d;
  } catch (_err) {
    const d = await fetchWithBaseFallback("/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const token = d?.accessToken || d?.token || d?.data?.accessToken || d?.data?.token;
    if (!token) throw new Error("Login succeeded but token missing");
    setStoredToken(token);
    return d;
  }
}

async function doLogout() {
  setStoredToken("");
  try {
    await fetchWithBaseFallback("/admin-dashboard-auth/logout", {
      method: "POST",
      headers: { Accept: "application/json" },
    });
  } catch {
    // ignore cookie logout failures in token mode
  }
}

function setAuthState(online, label) {
  authDot.classList.toggle("online", online);
  authLabel.textContent = label;
}

async function checkAuth() {
  const token = getStoredToken();
  if (token) {
    try {
      await apiFetch("/admin/users?page=1&limit=1");
      setAuthState(true, "متصل ✓");
      return true;
    } catch {
      setStoredToken("");
    }
  }
  try {
    await apiFetch("/admin-dashboard-auth/status");
    setAuthState(true, "متصل ✓");
    return true;
  } catch {
    setAuthState(false, "غير مسجل");
    return false;
  }
}

// ============================================================
// LOADERS
// ============================================================

// --- OVERVIEW ---
async function loadOverview() {
  const d    = await apiFetch("/admin-dashboard/overview");
  const data = d.data || {};
  document.getElementById("ovUsers").textContent    = data.usersCount    ?? "--";
  document.getElementById("ovRooms").textContent    = data.roomsCount    ?? "--";
  document.getElementById("ovAgencies").textContent = data.agenciesCount ?? "--";
  document.getElementById("ovPending").textContent  = data.pendingAgencies ?? "--";
}

// --- USERS ---
async function loadUsers() {
  const page  = Number(document.getElementById("usersPage").value  || 1);
  const limit = Number(document.getElementById("usersLimit").value || 30);
  const search = (document.getElementById("usersSearch")?.value || "").trim();
  const q     = `?page=${encodeURIComponent(page)}&limit=${encodeURIComponent(limit)}&search=${encodeURIComponent(search)}`;

  const d     = await apiFetch("/admin-dashboard/users" + q);
  const tbody = document.querySelector("#usersTable tbody");
  tbody.innerHTML = "";

  const rows = d.data || [];
  lastUsersRows = rows;
  for (const u of rows) {
    const tr = document.createElement("tr");
    const displayIdValue = Number(u.displayId || 0) >= 10000 ? `#${u.displayId}` : "—";
    tr.innerHTML = `
      <td><span class="cell-id">${escapeHtml(u.id ?? "")}</span></td>
      <td><span class="cell-id js-display-id">${escapeHtml(displayIdValue)}</span></td>
      <td>${escapeHtml(u.name ?? "")}</td>
      <td><span class="cell-muted">${escapeHtml(u.email ?? "")}</span></td>
      <td><span class="cell-muted">${escapeHtml(u.phone ?? "")}</span></td>
      <td><strong>${u.coinsBalance ?? u.coins ?? 0}</strong></td>
      <td>${u.isAdmin ? '<span class="badge badge-admin">أدمن</span>' : ""}</td>
      <td><span class="cell-muted">${fmtDate(u.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok" onclick="openCoinsModal('${escapeHtml(u.id ?? "")}')">+ كوينز</button>
          <button class="btn-outline" onclick="openDisplayIdModal(${Number(u.id || 0)}, this)">Change ID</button>
          <button class="btn-bad" onclick="toggleUserBan(${u.id}, ${u.isBanned ? "false" : "true"})">${u.isBanned ? "فك حظر" : "حظر"}</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  }

  const p = d.pagination || {};
  document.getElementById("usersMeta").textContent =
    `الصفحة ${p.page ?? page} / ${p.totalPages ?? "?"} — الإجمالي ${p.total ?? rows.length}`;
}

// --- ROOMS ---
async function loadRooms() {
  const d     = await apiFetch("/admin-dashboard/rooms");
  const tbody = document.querySelector("#roomsTable tbody");
  tbody.innerHTML = "";

  const rows = d.data || [];
  for (const r of rows) {
    const ownerName = r.owner?.name ? escapeHtml(r.owner.name) : "—";
    const cover = r.coverImageUrl
      ? `<a class="td-link" href="${r.coverImageUrl}" target="_blank">فتح ↗</a>`
      : "—";
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${escapeHtml(r.id ?? "")}</span></td>
      <td>${escapeHtml(r.name ?? "")}</td>
      <td><span class="cell-muted">${escapeHtml(r.type ?? "")}</span></td>
      <td>${r.maxSeats ?? "—"}</td>
      <td>${ownerName} <span class="cell-muted">#${r.owner?.id ?? ""}</span></td>
      <td>${cover}</td>
      <td>
  <button class="btn-bad" onclick="forceCloseRoom(${r.id})">إغلاق</button>
  <button class="btn-bad" onclick="deleteRoom(${r.id})" style="margin-left:4px">حذف</button>
</td>

      <td><span class="cell-muted">${fmtDate(r.createdAt)}</span></td>
      <td><button class="btn-bad" onclick="forceCloseRoom(${r.id})">إغلاق</button></td>
    `;
    tbody.appendChild(tr);
  }
}

// --- AGENCIES ---
async function loadAgencies() {
  const status = document.getElementById("agencyStatus").value;
  const q      = status ? `?status=${encodeURIComponent(status)}` : "";
  const d      = await apiFetch("/admin-dashboard/charging-agencies" + q);
  const tbody  = document.querySelector("#agenciesTable tbody");
  tbody.innerHTML = "";

  const rows = d.data || [];
  for (const a of rows) {
    const userName = a.user?.name ? escapeHtml(a.user.name) : "—";
    const imgs = [
      a.agencyImageUrl ? `<a class="td-link" href="${a.agencyImageUrl}" target="_blank">الوكالة</a>` : "",
      a.idFrontUrl     ? `<a class="td-link" href="${a.idFrontUrl}"     target="_blank">أمام</a>`    : "",
      a.idBackUrl      ? `<a class="td-link" href="${a.idBackUrl}"      target="_blank">خلف</a>`     : "",
    ].filter(Boolean).join(" · ");

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${a.id ?? ""}</span></td>
      <td>${userName} <span class="cell-muted">#${a.userId ?? ""}</span></td>
      <td>${escapeHtml(a.agencyName ?? "")}</td>
      <td><span class="cell-muted">${escapeHtml(a.phoneNumber ?? "")}</span></td>
      <td>${statusBadge(a.status ?? "pending")}</td>
      <td>${imgs || "—"}</td>
      <td><span class="cell-muted">${fmtDate(a.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok"      onclick="setAgencyStatus(${a.id}, 'approved')">قبول</button>
          <button class="btn-bad"     onclick="setAgencyStatus(${a.id}, 'rejected')">رفض</button>
          <button class="btn-ghost-sm" onclick="setAgencyStatus(${a.id}, 'pending')">مراجعة</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  }
}

async function setAgencyStatus(id, status) {
  try {
    await apiFetch(`/admin-dashboard/charging-agencies/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    showToast(`✓ تم تحديث الوكالة #${id} → ${statusText(status)}`);
    await loadOverview();
    await loadAgencies();
  if (document.getElementById("section-advanced")) await loadAdvanced();
  } catch (e) {
    showToast("خطأ: " + e.message);
  }
}

window.toggleUserBan = async function(userId, shouldBan) {
  const reason = shouldBan ? (prompt("سبب الحظر") || "Admin action") : null;
  if (shouldBan && !reason) return showToast("سبب الحظر مطلوب");
  await new Promise((resolve) => openConfirmModal("تأكيد الحظر", shouldBan ? "تأكيد حظر المستخدم؟" : "تأكيد فك الحظر؟", async () => {
    await apiFetch(`/admin-dashboard/users/${userId}/ban`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isBanned: !!shouldBan, reason }),
    });
    resolve();
  }));
  showToast("✓ تم تحديث حالة الحظر");
  await loadUsers();
};

window.forceCloseRoom = async function(roomId) {
  const reason = prompt("سبب إغلاق الغرفة") || "Admin force close";
  await new Promise((resolve) => openConfirmModal("تأكيد إغلاق الغرفة", "هل تريد إغلاق الغرفة الآن؟", async () => {
    await apiFetch(`/admin-dashboard/rooms/${roomId}/force-close`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    resolve();
  }));
  showToast("✓ تم إغلاق الغرفة");
  await loadRooms();
};

async function loadTransactions() {
  const userId = (document.getElementById("txUserId")?.value || "").trim();
  const type = (document.getElementById("txType")?.value || "").trim();
  const q = `?page=1&limit=30${userId ? `&userId=${encodeURIComponent(userId)}` : ""}${type ? `&type=${encodeURIComponent(type)}` : ""}`;
  const d = await apiFetchAny(['/admin-dashboard/transactions' + q, '/admin/transactions' + q]);
  const tb = document.querySelector('#transactionsTable tbody'); tb.innerHTML = '';
  const txRows = d.data || d.transactions || [];
  lastTransactionsRows = txRows;
  txRows.forEach((x) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${x.id}</td><td>${escapeHtml(x.user?.name || x.userId)}</td><td>${escapeHtml(x.type || '')}</td><td>${escapeHtml(x.status || '')}</td><td>${escapeHtml(x.amountCoins || '')}</td><td>${fmtDate(x.createdAt)}</td>`;
    tb.appendChild(tr);
  });
}

async function loadTopups() {
  const d = await apiFetch('/admin-dashboard/topup-requests?status=pending');
  const tb = document.querySelector('#topupsTable tbody'); tb.innerHTML = '';
  lastTopupsRows = (d.data || []);
  (d.data || []).forEach((x) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${x.id}</td><td>${escapeHtml(x.agency?.agencyName || '')}</td><td>${x.amount}</td><td>${escapeHtml(x.status)}</td><td><button class="btn-ok" onclick="reviewTopup(${x.id},'approved')">قبول</button> <button class="btn-bad" onclick="reviewTopup(${x.id},'rejected')">رفض</button></td>`;
    tb.appendChild(tr);
  });
}
window.reviewTopup = async (id, status) => { await apiFetch(`/admin-dashboard/topup-requests/${id}/review`, { method:'PATCH', headers:{'Content-Type':'application/json'}, body: JSON.stringify({status}) }); showToast('✓ تم مراجعة الطلب'); await loadTopups(); };

async function loadReports() {
  const d = await apiFetch('/admin-dashboard/reports?status=pending');
  const tb = document.querySelector('#reportsTable tbody'); tb.innerHTML = '';
  lastReportsRows = (d.data || []);
  (d.data || []).forEach((x) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${x.id}</td><td>${escapeHtml(x.reporter?.name || '')}</td><td>${escapeHtml(x.reportedUser?.name || '')}</td><td>${escapeHtml(x.reason || '')}</td><td>${escapeHtml(x.status || '')}</td><td><button class="btn-ok" onclick="reviewReport(${x.id},'resolved')">حل</button> <button class="btn-bad" onclick="reviewReport(${x.id},'dismissed')">رفض</button></td>`;
    tb.appendChild(tr);
  });
}
window.reviewReport = async (id, status) => { await apiFetch(`/admin-dashboard/reports/${id}`, { method:'PATCH', headers:{'Content-Type':'application/json'}, body: JSON.stringify({status}) }); showToast('✓ تم تحديث التقرير'); await loadReports(); };

async function loadAnalytics() { const d = await apiFetch('/admin-dashboard/analytics'); document.getElementById('analyticsBox').textContent = JSON.stringify(d.data || d, null, 2); }
async function sendBroadcast() { const title=document.getElementById('broadcastTitle').value.trim(); const message=document.getElementById('broadcastMessage').value.trim(); await apiFetch('/admin-dashboard/broadcast',{method:'POST',headers:{'Content-Type':'application/json'}, body:JSON.stringify({title,message})}); showToast('✓ تم إرسال البث'); }

async function loadQuests() {
  const d = await apiFetch('/admin-dashboard/quests');
  const tb = document.querySelector('#questsTable tbody'); tb.innerHTML = '';
  (d.data || []).forEach((q)=>{ const tr=document.createElement('tr'); tr.innerHTML=`<td>${q.id}</td><td>${escapeHtml(q.name)}</td><td>${escapeHtml(q.metric)}</td><td>${q.target}</td><td>${q.rewardCoins}</td><td><button class='btn-bad' onclick="deleteQuest('${q.id}')">حذف</button></td>`; tb.appendChild(tr); });
}
window.deleteQuest = async (id) => { await new Promise((resolve) => openConfirmModal('تأكيد حذف المهمة', 'هل تريد حذف المهمة؟', async () => { await apiFetch(`/admin-dashboard/quests/${id}`,{method:'DELETE'}); resolve(); })); showToast('✓ تم حذف المهمة'); await loadQuests(); };
async function createQuest() { await apiFetch('/admin-dashboard/quests',{method:'POST',headers:{'Content-Type':'application/json'}, body: JSON.stringify({ name:document.getElementById('qName').value, description:document.getElementById('qName').value, metric:document.getElementById('qMetric').value, target:Number(document.getElementById('qTarget').value||0), rewardCoins:Number(document.getElementById('qReward').value||0) })}); showToast('✓ تم إضافة المهمة'); await loadQuests(); }

async function loadLeaderboard() {
  const type = document.getElementById('leaderboardType').value;
  const d = await apiFetch(`/admin-dashboard/leaderboard?type=${encodeURIComponent(type)}`);
  const tb = document.querySelector('#leaderboardTable tbody'); tb.innerHTML='';
  lastLeaderboardRows = (d.data || []);
  (d.data || []).forEach((x, i)=>{ const value = x.coinsBalance ?? x.coinsSpent ?? x.xp ?? x.total ?? ''; const name = x.name || x.user?.name || x.owner?.name || `#${x.id || x.senderId || ''}`; const tr=document.createElement('tr'); tr.innerHTML=`<td>${i+1}</td><td>${escapeHtml(name)}</td><td>${escapeHtml(value)}</td>`; tb.appendChild(tr); });
}

async function loadAdvanced() { await Promise.all([loadTransactions(), loadTopups(), loadReports(), loadAnalytics(), loadQuests(), loadLeaderboard()]); }

// --- PRODUCTS ---
window.loadProducts = async function () {
  try {
    const d = await apiFetch("/store/products");
    const tbody = document.querySelector("#productsTable tbody");
    tbody.innerHTML = "";

    const rows = d.data || d.products || [];
    for (const p of rows) {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><span class="cell-id">${p.id}</span></td>
        <td>${escapeHtml(p.name)}</td>
        <td><span class="cell-muted">${p.type}</span></td>
        <td><strong>${p.price_coins}</strong></td>
        <td>
          ${p.type === "PROFILE_FRAME" || p.type === "FRAME"
            ? `<img src="${p.file_url}" width="44" height="44" style="border-radius:8px;object-fit:cover;" />`
            : "—"}
        </td>
        <td>
          ${p.type === "ENTRANCE_EFFECT"
            ? `<a class="td-link" href="${p.file_url}" target="_blank">▶ تشغيل</a>`
            : "—"}
        </td>
        <td>
          <button class="btn-bad" onclick="deleteProduct('${p.id}')">حذف</button>
        </td>
      `;
      tbody.appendChild(tr);
    }
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.deleteProduct = async function (id) {
  if (!confirm("هل أنت متأكد من حذف المنتج؟")) return;
  try {
    const res = await fetch(getApiBase() + "/admin/products/" + id, {
      method: "DELETE",
      credentials: "include",
    });
    const text = await res.text();
    if (!res.ok) throw new Error(text);
    showToast("✓ تم حذف المنتج");
    await loadProducts();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.addProduct = async function () {
  try {
    const fileInput = document.getElementById("p_file");
    const file = fileInput.files[0];
    if (!file) return showToast("❗ اختر ملفاً أولاً");

    const formData = new FormData();
    formData.append("name",        document.getElementById("p_name").value);
    formData.append("type",        document.getElementById("p_type").value);
    formData.append("price_coins", document.getElementById("p_price").value);
    formData.append("file", file);

    const res = await fetch(getApiBase() + "/admin-products/products", {
      method: "POST",
      body: formData,
      credentials: "include",
    });

    const text = await res.text();
    if (!res.ok) throw new Error(text);

    showToast("✓ تم رفع المنتج");
    await loadProducts();
  } catch (e) {
    showToast("❌ " + e.message);
  }
};

window.loadGifts = async function () {
  const d = await apiFetchAny(["/admin-dashboard/gifts", "/admin/gifts"]);
  const rows = d.data || d.gifts || [];
  const tbody = document.querySelector("#giftsTable tbody");
  tbody.innerHTML = "";
  rows.forEach((g) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${g.id}</td>
      <td>${escapeHtml(g.nameAr || g.name)}</td>
      <td>${
        normalizeGiftImageUrl(g.imageUrl)
          ? `<img src="${normalizeGiftImageUrl(g.imageUrl)}" width="44" height="44" style="border-radius:8px;object-fit:cover;" />`
          : '<span class="cell-muted">—</span>'
      }</td>
      <td>${g.coinsValue ?? g.priceCoins}</td>
      <td>${g.sortOrder ?? 0}</td>
      <td>${g.isActive ? "✅" : "⛔"}</td>
      <td>
        <button class="btn btn-outline" onclick="openGiftModal(${g.id})">تعديل</button>
        <button class="btn-bad" onclick="removeGift(${g.id})">حذف</button>
      </td>
    `;
    tbody.appendChild(tr);
  });
};

window.uploadGiftImage = async function () {
  const fileInput = document.getElementById("gift_imageFile");
  const file = fileInput?.files?.[0];
  if (!file) return showToast("اختر صورة من الجهاز أولاً");

  const formData = new FormData();
  formData.append("image", file);

  const d = await apiFetch("/upload/image", {
    method: "POST",
    body: formData,
  });

  const imageUrl = d?.url || d?.imageUrl;
  if (!imageUrl) throw new Error("لم يتم إرجاع رابط الصورة");

  document.getElementById("gift_imageUrl").value = imageUrl;
  const preview = document.getElementById("giftImagePreview");
  preview.src = imageUrl;
  preview.style.display = "block";
  showToast("✓ تم رفع صورة الهدية");
};

window.openGiftModal = async function (id = null) {
  const modal = document.getElementById('giftModal');
  const title = document.getElementById('giftModalTitle');
  const form = document.getElementById('giftForm');
  const idInput = document.getElementById('gift_id');

  form.reset();
  idInput.value = '';
  title.textContent = id ? 'تعديل هدية' : 'إضافة هدية';

  if (id) {
    const d = await apiFetchAny(['/admin-dashboard/gifts', '/admin/gifts']);
    const gift = (d.data || d.gifts || []).find((g) => Number(g.id) === Number(id));
    if (!gift) throw new Error('الهدية غير موجودة');
    idInput.value = String(gift.id);
    document.getElementById('gift_nameAr').value = gift.nameAr || gift.name || '';
    document.getElementById('gift_imageUrl').value = gift.imageUrl || '';
    document.getElementById('gift_animationUrl').value = gift.animationUrl || '';
    document.getElementById('gift_coinsValue').value = gift.coinsValue ?? gift.priceCoins ?? 0;
    document.getElementById('gift_sortOrder').value = gift.sortOrder ?? 0;
    document.getElementById('gift_isActive').checked = Boolean(gift.isActive);
    const preview = document.getElementById("giftImagePreview");
    const safeGiftImage = normalizeGiftImageUrl(gift.imageUrl);
    if (safeGiftImage) {
      preview.src = safeGiftImage;
      preview.style.display = "block";
    } else {
      preview.style.display = "none";
    }
  } else {
    document.getElementById('gift_isActive').checked = true;
    document.getElementById("giftImagePreview").style.display = "none";
  }
  document.getElementById("gift_imageFile").value = "";

  modal.classList.remove('hidden');
};

window.closeGiftModal = function () {
  document.getElementById('giftModal').classList.add('hidden');
};

window.saveGift = async function () {
  const id = document.getElementById('gift_id').value.trim();
  const payload = {
    nameAr: document.getElementById('gift_nameAr').value.trim(),
    imageUrl: document.getElementById('gift_imageUrl').value.trim(),
    animationUrl: document.getElementById('gift_animationUrl').value.trim() || null,
    coinsValue: Number(document.getElementById('gift_coinsValue').value || 0),
    sortOrder: Number(document.getElementById('gift_sortOrder').value || 0),
    isActive: document.getElementById('gift_isActive').checked,
  };

  if (!payload.nameAr || !payload.imageUrl || payload.coinsValue <= 0) {
    return showToast('❗ nameAr / imageUrl / coinsValue مطلوبة');
  }

  if (id) {
    await apiFetchAny([`/admin-dashboard/gifts/${id}`, `/admin/gifts/${id}`], {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    showToast('✓ تم تعديل الهدية');
  } else {
    await apiFetchAny(['/admin-dashboard/gifts', '/admin/gifts'], {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    showToast('✓ تم إضافة الهدية');
  }

  closeGiftModal();
  await loadGifts();
};

window.removeGift = async function (id) {
  await apiFetchAny([`/admin-dashboard/gifts/${id}`, `/admin/gifts/${id}`], { method: 'DELETE' });
  showToast('✓ تم حذف الهدية');
  await loadGifts();
};
// File input type switching
const typeSelect   = document.getElementById("p_type");
const fileLabelText = document.getElementById("fileLabelText");
const p_fileInput  = document.getElementById("p_file");

typeSelect.addEventListener("change", () => {
  if (typeSelect.value === "avatar_frame" || typeSelect.value === "frame") {
    p_fileInput.accept     = "image/*";
    fileLabelText.textContent = "اختر صورة الإطار";
  } else {
    p_fileInput.accept     = "video/*";
    fileLabelText.textContent = "اختر ملف الفيديو";
  }
});

// Click file label triggers file input
document.getElementById("fileLabel").addEventListener("click", () => {
  p_fileInput.click();
});

p_fileInput.addEventListener("change", () => {
  const name = p_fileInput.files[0]?.name;
  if (name) fileLabelText.textContent = name;
});

// ============================================================
// COINS MODAL
// ============================================================
let selectedUserId = null;

window.openCoinsModal = function (userId) {
  selectedUserId = userId;
  document.getElementById("coinsAmount").value = "";
  document.getElementById("coinsModal").classList.remove("hidden");
};

window.closeCoinsModal = function () {
  selectedUserId = null;
  document.getElementById("coinsModal").classList.add("hidden");
};

window.confirmAddCoins = async function () {
  try {
    const amount = Number(document.getElementById("coinsAmount").value);
    if (!amount || amount <= 0) return showToast("❗ أدخل رقماً صحيحاً");

    const res = await fetch(getApiBase() + "/admin/users/" + selectedUserId + "/coins/add", {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount }),
    });

    const text = await res.text();
    if (!res.ok) throw new Error(text);

    showToast("✓ تم إضافة الكوينز بنجاح");
    closeCoinsModal();
    await loadUsers();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// ============================================================
// EVENT LISTENERS
// ============================================================
document.getElementById("btnSave").addEventListener("click", () => {
  localStorage.setItem(LS_API, apiEl.value.trim());
  apiBaseText.textContent = getApiBase() || "--";
  // sync settings input
  const settingsInput = document.getElementById("apiBaseSettings");
  if (settingsInput) settingsInput.value = apiEl.value.trim();
  showToast("✓ تم حفظ قاعدة الـ API");
});

document.getElementById("btnSaveSettings")?.addEventListener("click", () => {
  const val = document.getElementById("apiBaseSettings").value.trim();
  apiEl.value = val;
  localStorage.setItem(LS_API, val);
  apiBaseText.textContent = val || "--";
  showToast("✓ تم حفظ الإعدادات");
});

document.getElementById("btnReload").addEventListener("click", async () => {
  try {
    await loadAll();
    showToast("✓ تم تحديث البيانات");
  } catch (e) {
    showToast("خطأ: " + e.message);
  }
});

async function handleLogin() {
  try {
    const email    = document.getElementById("loginEmail").value.trim();
    const password = document.getElementById("loginPassword").value;
    if (!email || !password) return showToast("أدخل الإيميل وكلمة المرور");

    await doLogin(email, password);
    setAuthState(true, "متصل ✓");
    showToast("✓ تم تسجيل الدخول");
    await loadAll();
  } catch (e) {
    showToast("فشل تسجيل الدخول: " + e.message);
  }
}

document.getElementById("loginForm")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  await handleLogin();
});

document.getElementById("btnLogin").addEventListener("click", async (e) => {
  e.preventDefault();
  await handleLogin();
});

document.getElementById("btnLogout").addEventListener("click", async () => {
  try {
    await doLogout();
    setAuthState(false, "غير مسجل");
    showToast("✓ تم تسجيل الخروج");
  } catch (e) {
    showToast("خطأ: " + e.message);
  }
});

document.getElementById("btnUsers").addEventListener("click", async () => {
  try { await loadUsers();    showToast("✓ تم تحميل المستخدمين"); } catch (e) { showToast("خطأ: " + e.message); }
});

document.getElementById("btnRooms").addEventListener("click", async () => {
  try { await loadRooms();    showToast("✓ تم تحميل الغرف"); }        catch (e) { showToast("خطأ: " + e.message); }
});

document.getElementById("btnAgencies").addEventListener("click", async () => {
  try { await loadAgencies(); showToast("✓ تم تحميل الوكالات"); }     catch (e) { showToast("خطأ: " + e.message); }
});

document.getElementById("btnTransactions")?.addEventListener("click", () => loadTransactions().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnTopups")?.addEventListener("click", () => loadTopups().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnReports")?.addEventListener("click", () => loadReports().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAnalytics")?.addEventListener("click", () => loadAnalytics().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnLeaderboard")?.addEventListener("click", () => loadLeaderboard().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnBroadcast")?.addEventListener("click", () => sendBroadcast().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnQuests")?.addEventListener("click", () => loadQuests().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnQuestCreate")?.addEventListener("click", () => createQuest().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAdvancedRefresh")?.addEventListener("click", () => loadAdvanced().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnLoadGifts")?.addEventListener("click", () => loadGifts().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("giftSaveBtn")?.addEventListener("click", () => saveGift().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("giftUploadImageBtn")?.addEventListener("click", () => uploadGiftImage().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAddGift")?.addEventListener("click", () => openGiftModal().catch(e => showToast("خطأ: " + e.message)));


document.getElementById("btnUsersExport")?.addEventListener("click", () => downloadCSV("users.csv", lastUsersRows));
document.getElementById("btnTransactionsExport")?.addEventListener("click", () => downloadCSV("transactions.csv", lastTransactionsRows));
document.getElementById("btnTopupsExport")?.addEventListener("click", () => downloadCSV("topups.csv", lastTopupsRows));
document.getElementById("btnReportsExport")?.addEventListener("click", () => downloadCSV("reports.csv", lastReportsRows));
document.getElementById("btnLeaderboardExport")?.addEventListener("click", () => downloadCSV("leaderboard.csv", lastLeaderboardRows));
document.getElementById("btnLiveToggle")?.addEventListener("click", (e) => {
  liveMode = !liveMode;
  e.target.textContent = liveMode ? "إيقاف التحديث الحي" : "تشغيل التحديث الحي";
  if (liveMode) startLiveRefresh(); else stopLiveRefresh();
});

function startLiveRefresh() {
  stopLiveRefresh();
  liveTimer = setInterval(() => {
    if (!liveMode) return;
    loadOverview().catch(()=>{});
    loadAdvanced().catch(()=>{});
  }, 20000);
}
function stopLiveRefresh() { if (liveTimer) clearInterval(liveTimer); liveTimer = null; }

// expose for inline agency buttons
window.setAgencyStatus = setAgencyStatus;

// ============================================================
// LOAD ALL
// ============================================================
async function loadAll() {
  await loadOverview();
  await loadUsers();
  await loadRooms();
  await loadAgencies();
  if (document.getElementById("section-advanced")) await loadAdvanced();
  if (document.getElementById("giftsTable")) await loadGifts();
}

// ============================================================
// BOOT
// ============================================================
(function init() {
  const saved = localStorage.getItem(LS_API) || getApiBase();
  apiEl.value = saved;
  const settingsInput = document.getElementById("apiBaseSettings");
  if (settingsInput) settingsInput.value = saved;
  apiBaseText.textContent = saved || "--";

  checkAuth().then(ok => {
    if (ok) {
      loadAll().catch(e => showToast("خطأ: " + e.message));
      startLiveRefresh();
    }
  });
})();
