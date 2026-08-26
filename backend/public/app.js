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
  vip:       "مستويات VIP",
  levels:    "مستويات LV",
  admins:    "المشرفون",
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
  if (sec === "vip") loadVipLevels().catch(e => showToast("خطأ: " + e.message));
  if (sec === "levels") loadLvLevels().catch(e => showToast("خطأ: " + e.message));
  if (sec === "admins") loadAdmins().catch(e => showToast("خطأ: " + e.message));
  if (sec === "settings") { try { window.loadCpSettings && window.loadCpSettings(); } catch (_) {} try { window.loadTargetTiers && window.loadTargetTiers(); } catch (_) {} try { window.loadTargetSellPolicy && window.loadTargetSellPolicy(); } catch (_) {} }
}

// ============================================================
// SIDEBAR TOGGLE (mobile)
// ============================================================
const sidebar       = document.getElementById("sidebar");
const sidebarToggle = document.getElementById("sidebarToggle");

// Tap-anywhere-outside backdrop. Created once and reused; on desktop the CSS
// hides it entirely, so it costs nothing there.
const sidebarBackdrop = document.createElement("div");
sidebarBackdrop.className = "sidebar-backdrop";
document.body.appendChild(sidebarBackdrop);

function setSidebar(open) {
  sidebar.classList.toggle("open", open);
  sidebarBackdrop.classList.toggle("show", open);
  // Stop the page scrolling behind the open drawer.
  document.body.style.overflow = open ? "hidden" : "";
}

sidebarToggle.addEventListener("click", () => {
  setSidebar(!sidebar.classList.contains("open"));
});

sidebarBackdrop.addEventListener("click", () => setSidebar(false));

// Picking a section closes the drawer on phones — otherwise it covers the
// content the user just asked for.
document.querySelectorAll(".nav-item").forEach((item) => {
  item.addEventListener("click", () => {
    if (window.matchMedia("(max-width: 768px)").matches) setSidebar(false);
  });
});

// Rotating to landscape / resizing past the breakpoint must not leave the page
// stuck with a hidden scrollbar.
window.addEventListener("resize", () => {
  if (!window.matchMedia("(max-width: 768px)").matches) setSidebar(false);
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

function normalizeApiBase(raw) {
  let base = (raw || "").trim();
  if (!base) return "";

  if (!/^https?:\/\//i.test(base)) {
    base = "http://" + base;
  }

  // Repair frequent malformed inputs:
  // - "http://host/:3000" -> "http://host:3000"
  // - "http://host/3000"  -> "http://host:3000"
  base = base.replace(/^(https?:\/\/[^/]+)\/:(\d+)(.*)$/i, "$1:$2$3");
  base = base.replace(/^(https?:\/\/[^/:?#]+)\/(\d{2,5})(?=\/|$)(.*)$/i, "$1:$2$3");

  try {
    const u = new URL(base);
    const cleanPath = (u.pathname || "").replace(/\/+$/, "");
    return `${u.protocol}//${u.host}${cleanPath}`;
  } catch {
    return base.replace(/\/+$/, "");
  }
}

function getDefaultApiBase() {
  const origin = String(window.location.origin || "").replace(/\/+$/, "");
  if (!origin) return "";
  if (origin.endsWith("/api/v1")) return origin;
  return origin + "/api/v1";
}


function getApiBase() {
  return normalizeApiBase(apiEl.value);
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
  const candidates = [];

  if (normalized.endsWith("/api/v1")) {
    candidates.push(normalized);
    candidates.push(normalized.slice(0, -"/api/v1".length));
  } else {
    // Prefer versioned APIs first to avoid noisy 404s on deployments
    // that only expose routes under /api/v1.
    candidates.push(normalized + "/api/v1");
    candidates.push(normalized);
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
    let res;

    try {
      res = await fetch(base + path, {
        ...opts,
        credentials: "include",
        headers: Object.assign({ Accept: "application/json" }, authHeaders, opts.headers || {}),
      });
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
      continue;
    }

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
      <td><span class="cell-muted">${escapeHtml(genderLabel(u.gender))}</span></td>
      <td><strong>${u.coinsBalance ?? u.coins ?? 0}</strong></td>
      <td>
        <span class="cell-muted">Lv.${u.level ?? 1} · VIP${u.vipLevel ?? 0}${u.target ? ` · 🎯${u.target.targetGoalCoins}` : ""}</span>
      </td>
      <td>${u.isAdmin ? '<span class="badge badge-admin">أدمن</span>' : ""}</td>
      <td><span class="cell-muted">${fmtDate(u.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok" onclick="openCoinsModal('${escapeHtml(u.id ?? "")}', 'add')">+ كوينز</button>
          <button class="btn-bad" onclick="openCoinsModal('${escapeHtml(u.id ?? "")}', 'remove')">- كوينز</button>
          <button class="btn-outline" onclick="openDisplayIdModal(${Number(u.id || 0)}, this)">Change ID</button>
          <button class="btn-outline" onclick="openEditProfileModal(${Number(u.id || 0)}, ${JSON.stringify(u.name ?? "").replace(/"/g, '&quot;')}, '${escapeHtml(u.gender ?? "")}', ${u.nameLocked ? "true" : "false"})">تعديل</button>
          <button class="btn-outline" onclick="openProgressionModal(${Number(u.id || 0)}, ${Number(u.level || 1)}, ${Number(u.xp || 0)}, ${Number(u.vipLevel || 0)})">المستوى/VIP</button>
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

// --- ROOMS (group 6) ---
async function loadRooms() {
  const search = (document.getElementById("roomSearch")?.value || "").trim();
  const q = search ? `?search=${encodeURIComponent(search)}` : "";
  const d     = await apiFetch("/admin-dashboard/rooms" + q);
  const tbody = document.querySelector("#roomsTable tbody");
  tbody.innerHTML = "";

  const rows = d.data || [];
  for (const r of rows) {
    const ownerName = r.owner?.name ? escapeHtml(r.owner.name) : "—";
    const cover = r.coverImageUrl
      ? `<a class="td-link" href="${r.coverImageUrl}" target="_blank">فتح ↗</a>`
      : "—";
    const status = [
      r.isActive ? `<span class="cell-muted">مفتوحة</span>` : `<span style="color:#e05555">مغلقة</span>`,
      r.isLocked ? `🔒` : ``,
      r.nameLocked ? `📌` : ``,
    ].filter(Boolean).join(" ");
    const toggleBtn = r.isActive
      ? `<button class="btn-bad" onclick="forceCloseRoom(${r.id})">إغلاق</button>`
      : `<button class="btn-ok" onclick="reopenRoom(${r.id})">فتح</button>`;
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${escapeHtml(r.id ?? "")}</span></td>
      <td>${escapeHtml(r.name ?? "")}</td>
      <td><span class="cell-muted">${escapeHtml(r.type ?? "")}</span></td>
      <td>${status}</td>
      <td>${r.maxSeats ?? "—"}</td>
      <td>${ownerName} <span class="cell-muted">#${r.owner?.displayId ?? r.owner?.id ?? ""}</span></td>
      <td>${cover}</td>
      <td><span class="cell-muted">${fmtDate(r.createdAt)}</span></td>
      <td>
        <button class="btn-ok" onclick="openEditRoomModal(${r.id}, '${escapeHtml(r.name ?? "").replace(/'/g, "\\'")}', ${!!r.nameLocked})">تعديل</button>
        <button class="btn-ok" onclick="openEditProfileModal(${r.owner?.id ?? 0}, '${escapeHtml(r.owner?.name ?? "").replace(/'/g, "\\'")}', '', ${!!r.owner?.nameLocked})">المالك</button>
        <button class="btn-ok" onclick="openRoomDetails(${r.id})">تفاصيل</button>
        ${toggleBtn}
      </td>
    `;
    tbody.appendChild(tr);
  }
}

// Room edit modal (name + nameLocked)
let editRoomId = null;
window.openEditRoomModal = function (roomId, name, nameLocked) {
  editRoomId = roomId;
  document.getElementById("editRoomSub").textContent = `غرفة #${roomId}`;
  document.getElementById("editRoomName").value = name || "";
  document.getElementById("editRoomNameLocked").checked = !!nameLocked;
  document.getElementById("editRoomModal").classList.remove("hidden");
};
window.closeEditRoomModal = function () {
  editRoomId = null;
  document.getElementById("editRoomModal").classList.add("hidden");
};
window.confirmEditRoom = async function () {
  try {
    if (!editRoomId) return;
    const name = document.getElementById("editRoomName").value.trim();
    const nameLocked = document.getElementById("editRoomNameLocked").checked;
    const body = { nameLocked };
    if (name) body.name = name;
    await apiFetch(`/admin-dashboard/rooms/${editRoomId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast("✓ تم حفظ تعديلات الغرفة");
    closeEditRoomModal();
    await loadRooms();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update room"));
  }
};

// Room details modal (who's inside + PIN for locked rooms)
window.openRoomDetails = async function (roomId) {
  try {
    const d = await apiFetch(`/admin-dashboard/rooms/${roomId}/details`);
    const r = d.data || {};
    document.getElementById("roomDetailsSub").textContent =
      `غرفة #${r.id} — ${r.name || ""} (${r.isActive ? "مفتوحة" : "مغلقة"})`;
    const pinEl = document.getElementById("roomDetailsPin");
    pinEl.innerHTML = r.isLocked
      ? `<label class="modal-sub">🔒 غرفة مقفلة — كلمة المرور: <strong style="direction:ltr">${escapeHtml(r.accessCode || "غير محددة")}</strong></label>`
      : `<label class="modal-sub">غرفة غير مقفلة</label>`;
    document.getElementById("roomDetailsCount").textContent = r.membersCount ?? 0;
    const tb = document.querySelector("#roomMembersTable tbody");
    tb.innerHTML = "";
    (r.membersInside || []).forEach((m) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `<td><span class="cell-id">${escapeHtml(m.displayId ?? m.id)}</span></td><td>${escapeHtml(m.name || "")}</td>`;
      tb.appendChild(tr);
    });
    document.getElementById("roomDetailsModal").classList.remove("hidden");
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to load room details"));
  }
};
window.closeRoomDetailsModal = function () {
  document.getElementById("roomDetailsModal").classList.add("hidden");
};

window.reopenRoom = async function (roomId) {
  try {
    await apiFetch(`/admin-dashboard/rooms/${roomId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isActive: true }),
    });
    showToast("✓ تم فتح الغرفة");
    await loadRooms();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to reopen room"));
  }
};

// --- AGENCY REQUESTS (new, awaiting approval) ---
window.loadAgencyRequests = async function () {
  const type = document.getElementById("agencyRequestType")?.value || "";
  const q = `?status=pending${type ? `&type=${encodeURIComponent(type)}` : ""}`;
  const d = await apiFetch("/admin-dashboard/agency-requests" + q);
  const tbody = document.querySelector("#agencyRequestsTable tbody");
  if (!tbody) return;
  tbody.innerHTML = "";
  const rows = d.data || [];
  if (!rows.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="cell-muted" style="text-align:center;padding:14px">لا توجد طلبات قيد المراجعة</td></tr>';
    return;
  }
  for (const r of rows) {
    const typeLabel = r.type === "HOSTING" ? "استضافة" : "شحن";
    const img = r.imageUrl ? `<a class="td-link" href="${r.imageUrl}" target="_blank">عرض</a>` : "—";
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${r.id}</span></td>
      <td>${escapeHtml(r.user?.name ?? "")} <span class="cell-muted">#${r.user?.displayId ?? r.userId}</span></td>
      <td>${escapeHtml(r.agencyName ?? "")}</td>
      <td><span class="cell-muted">${typeLabel}</span></td>
      <td><span class="cell-muted">${escapeHtml(r.contactInfo ?? "—")}</span></td>
      <td>${img}</td>
      <td><span class="cell-muted">${fmtDate(r.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok"  onclick="reviewAgencyRequest(${r.id}, 'approved')">قبول</button>
          <button class="btn-bad" onclick="reviewAgencyRequest(${r.id}, 'rejected')">رفض</button>
        </div>
      </td>`;
    tbody.appendChild(tr);
  }
};

window.reviewAgencyRequest = async function (id, status) {
  try {
    await apiFetch(`/admin-dashboard/agency-requests/${id}/review`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    showToast(status === "approved" ? "✓ تم قبول الوكالة" : "تم رفض الطلب");
    await loadAgencyRequests();
    await loadAgencies();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// --- AGENCIES ---
// ============================================================
// B11 — مكافآت الشحن التلقائية: ladder of "charge N coins -> get this".
// ============================================================
let acrItemSelection = new Set();
let acrAllProducts = [];

async function loadAgencyChargeRewards() {
  const tbody = document.querySelector("#agencyChargeRewardsTable tbody");
  if (!tbody) return;

  const [d, productsRes] = await Promise.all([
    apiFetch("/admin-dashboard/agency-charge-rewards"),
    apiFetchAny(["/admin-products/products", "/store/products"]).catch(() => ({ data: [] })),
  ]);
  acrAllProducts = productsRes.data || productsRes.products || [];
  const byId = new Map(acrAllProducts.map((p) => [p.id, p]));

  tbody.innerHTML = "";
  for (const r of d.data || []) {
    const items = (r.rewardItemIds || [])
      .map((id) => byId.get(id)?.name)
      .filter(Boolean)
      .map(escapeHtml)
      .join("، ");
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>${Number(r.thresholdCoins ?? 0).toLocaleString("en-US")}</strong></td>
      <td>${Number(r.rewardCoins ?? 0).toLocaleString("en-US")}</td>
      <td><span class="cell-muted">${items || "—"}</span></td>
      <td><span class="cell-muted">${r.agencyId ? "#" + r.agencyId : "كل الوكالات"}</span></td>
      <td><button class="btn-bad" onclick="deleteAgencyChargeReward(${r.id})">حذف</button></td>
    `;
    tbody.appendChild(tr);
  }
}

window.openAcrItemsModal = function () {
  const listEl = document.getElementById("acrItemsList");
  listEl.innerHTML = acrAllProducts.length
    ? acrAllProducts.map((p) => `
        <label style="display:flex;align-items:center;gap:8px;padding:4px 2px;cursor:pointer">
          <input type="checkbox" class="acr-item-check" value="${p.id}" ${acrItemSelection.has(p.id) ? "checked" : ""} />
          <span>${escapeHtml(p.name)}</span>
          <span class="cell-muted">${VIP_REWARD_TYPE_LABELS[p.type] || p.type}</span>
        </label>`).join("")
    : '<p class="cell-muted">لا توجد منتجات — أضف منتجات أولاً</p>';
  document.getElementById("acrItemsModal").classList.remove("hidden");
};

window.closeAcrItemsModal = function () {
  document.getElementById("acrItemsModal").classList.add("hidden");
};

window.confirmAcrItems = function () {
  acrItemSelection = new Set(
    [...document.querySelectorAll(".acr-item-check:checked")].map((el) => el.value),
  );
  const btn = document.getElementById("acr_items_btn");
  if (btn) btn.textContent = `🎁 منتجات (${acrItemSelection.size})`;
  closeAcrItemsModal();
};

window.saveAgencyChargeReward = async function () {
  try {
    const thresholdCoins = Number(document.getElementById("acr_threshold").value);
    const rewardCoins = Number(document.getElementById("acr_coins").value || 0);
    const agencyRaw = document.getElementById("acr_agency").value.trim();
    if (!thresholdCoins || thresholdCoins <= 0) return showToast("❗ أدخل عتبة شحن صحيحة");
    if (rewardCoins <= 0 && acrItemSelection.size === 0) {
      return showToast("❗ حدد كوينزات أو منتجات للمكافأة");
    }
    await apiFetch("/admin-dashboard/agency-charge-rewards", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        thresholdCoins,
        rewardCoins,
        rewardItemIds: [...acrItemSelection],
        agencyId: agencyRaw === "" ? null : Number(agencyRaw),
      }),
    });
    document.getElementById("acr_threshold").value = "";
    document.getElementById("acr_coins").value = "";
    document.getElementById("acr_agency").value = "";
    acrItemSelection = new Set();
    const btn = document.getElementById("acr_items_btn");
    if (btn) btn.textContent = "🎁 منتجات (0)";
    showToast("✓ تم حفظ درجة المكافأة");
    await loadAgencyChargeRewards();
  } catch (e) {
    showToast("❌ " + e.message);
  }
};

window.deleteAgencyChargeReward = async function (id) {
  if (!confirm("حذف درجة المكافأة؟")) return;
  try {
    await apiFetch(`/admin-dashboard/agency-charge-rewards/${id}`, { method: "DELETE" });
    showToast("✓ تم الحذف");
    await loadAgencyChargeRewards();
  } catch (e) {
    showToast("❌ " + e.message);
  }
};

async function loadAgencies() {
  try { await loadAgencyRequests(); } catch (_) {}
  try { await loadAgencyChargeRewards(); } catch (_) {}

  // #23: "assigned by me" is a separate, unfiltered view — the agencies this
  // specific admin directly created via تعيين وكالة مباشرة.
  const onlyMine = document.getElementById("assignedByMeFilter")?.checked;
  let d;
  if (onlyMine) {
    d = await apiFetch("/admin-dashboard/agencies/assigned-by-me");
  } else {
    const status = document.getElementById("agencyStatus").value;
    const type   = document.getElementById("agencyType")?.value || "";
    const search = (document.getElementById("agencySearch")?.value || "").trim();
    const params = new URLSearchParams();
    if (status) params.set("status", status);
    if (type)   params.set("type", type);
    if (search) params.set("search", search);
    const qs = params.toString();
    d = await apiFetch("/admin-dashboard/charging-agencies" + (qs ? `?${qs}` : ""));
  }
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
    const safeName = escapeHtml(a.agencyName ?? "").replace(/'/g, "\\'");

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${a.id ?? ""}</span></td>
      <td>${userName} <span class="cell-muted">#${a.user?.displayId ?? a.userId ?? ""}</span></td>
      <td>
        ${escapeHtml(a.agencyName ?? "")} ${a.nameLocked ? "📌" : ""}
        ${a.type === "HOSTING" ? "" : `<div class="cell-muted">رصيد المحفظة: ${Number(a.balanceCoins ?? 0).toLocaleString("en-US")}</div>`}
      </td>
      <td><span class="cell-muted">${a.type === "HOSTING" ? "استضافة" : "شحن"}</span></td>
      <td><span class="cell-muted">${escapeHtml(a.phoneNumber ?? "")}</span></td>
      <td>${statusBadge(a.status ?? "pending")}</td>
      <td>${
        a.type === "HOSTING"
          ? '<span class="cell-muted">—</span>'
          : `<strong>${Number(a.selfChargeCount ?? 0).toLocaleString("en-US")}</strong> مرة`
            + `<div class="cell-muted">${Number(a.selfChargeCoins ?? 0).toLocaleString("en-US")} كوينز</div>`
      }</td>
      <td>${imgs || "—"}</td>
      <td><span class="cell-muted">${fmtDate(a.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok"      onclick="setAgencyStatus(${a.id}, 'approved')">قبول</button>
          <button class="btn-bad"     onclick="setAgencyStatus(${a.id}, 'rejected')">رفض</button>
          <button class="btn-ghost-sm" onclick="setAgencyStatus(${a.id}, 'pending')">مراجعة</button>
          <button class="btn btn-outline" onclick="openEditAgencyModal(${a.id}, '${safeName}', ${!!a.nameLocked})">تعديل</button>
          <button class="btn btn-outline" onclick="showAgencyMembers(${a.id}, '${safeName}')">الأعضاء</button>
          <button class="btn btn-outline" onclick="setAgencyTarget(${a.id}, '${safeName}', ${Number(a.targetCoins ?? 0)})">التارجت</button>
          ${a.type === "HOSTING" ? "" : `<button class="btn btn-outline" onclick="showAgencyCharges(${a.id}, '${safeName}')">الشحنات</button>`}
          ${a.type === "HOSTING" ? "" : `<button class="btn btn-primary" onclick="topupAgencyBalance(${a.id}, '${safeName}', ${Number(a.balanceCoins ?? 0)})">شحن رصيد</button>`}
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  }
}

// شحن رصيد الوكالة: credits the charging agency's WALLET — the pot it sends
// coins to users from. Distinct from التارجت (a goal) and from approving a
// topup request (the agent asking for it). Adds to the balance, never replaces
// it, so entering 500000 twice leaves 1,000,000.
window.topupAgencyBalance = async function (id, name, current) {
  const currentText = Number(current ?? 0).toLocaleString("en-US");
  const input = prompt(
    `شحن رصيد وكالة ${name}\nالرصيد الحالي: ${currentText} كوينز\n\nأدخل المبلغ المراد إضافته:`,
    ""
  );
  if (input === null) return;

  const amount = Number(String(input).trim());
  if (!Number.isFinite(amount) || amount <= 0) {
    return showToast("❗ أدخل مبلغاً أكبر من صفر");
  }
  if (!confirm(`إضافة ${amount.toLocaleString("en-US")} كوينز إلى محفظة وكالة ${name}؟`)) return;

  try {
    const d = await apiFetch(`/admin-dashboard/agencies/${id}/topup`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount }),
    });
    const balance = Number(d?.data?.balanceCoins ?? 0).toLocaleString("en-US");
    showToast(`✓ تم الشحن — الرصيد الجديد: ${balance} كوينز`);
    await loadAgencies();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// تارجت الوكيل: the goal an AGENT is held to, set here by the platform admin.
// Progress against it is the agency's whole production (all its hosts' gift
// earnings combined) and is computed live by the API — this only sets the bar.
window.setAgencyTarget = async function (id, name, current) {
  const input = prompt(`تارجت وكالة ${name} (كوينز)\n0 = بدون تارجت`, String(current ?? 0));
  if (input === null) return;
  const targetCoins = Number(String(input).trim());
  if (!Number.isFinite(targetCoins) || targetCoins < 0) {
    return showToast("❗ أدخل رقماً صحيحاً (0 أو أكثر)");
  }
  try {
    await apiFetch(`/admin-dashboard/agencies/${id}/target`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ targetCoins }),
    });
    showToast("✓ تم تحديد التارجت");
    await loadAgencies();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to set target"));
  }
};

// Direct assign (#21): admin enters a user ID, picks HOSTING/CHARGING, no
// request/approval step. Separate from the self-service request flow above.
window.confirmAssignAgency = async function () {
  try {
    const userId = Number(document.getElementById("assignUserId").value);
    if (!userId) return showToast("❗ أدخل رقم المستخدم (ID)");
    const type = document.getElementById("assignAgencyType").value;
    const agencyName = document.getElementById("assignAgencyName").value.trim();

    await apiFetch("/admin-dashboard/agencies/assign", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userId, type, agencyName: agencyName || undefined }),
    });

    showToast("✓ تم تعيين الوكالة");
    document.getElementById("assignUserId").value = "";
    document.getElementById("assignAgencyName").value = "";
    await loadAgencies();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to assign agency"));
  }
};

// Agency edit modal (name + nameLocked) — group 7
let editAgencyId = null;
window.openEditAgencyModal = function (agencyId, name, nameLocked) {
  editAgencyId = agencyId;
  document.getElementById("editAgencySub").textContent = `وكالة #${agencyId}`;
  document.getElementById("editAgencyName").value = name || "";
  document.getElementById("editAgencyNameLocked").checked = !!nameLocked;
  document.getElementById("editAgencyModal").classList.remove("hidden");
};
window.closeEditAgencyModal = function () {
  editAgencyId = null;
  document.getElementById("editAgencyModal").classList.add("hidden");
};
window.confirmEditAgency = async function () {
  try {
    if (!editAgencyId) return;
    const agencyName = document.getElementById("editAgencyName").value.trim();
    const nameLocked = document.getElementById("editAgencyNameLocked").checked;
    const body = { nameLocked };
    if (agencyName) body.agencyName = agencyName;
    await apiFetch(`/admin-dashboard/agencies/${editAgencyId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast("✓ تم حفظ تعديلات الوكالة");
    closeEditAgencyModal();
    await loadAgencies();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update agency"));
  }
};

// Charge history modal: who was charged, how many coins, by whom — group 7
window.showAgencyCharges = async function (agencyId, agencyName) {
  try {
    const d = await apiFetch(`/admin-dashboard/agencies/${agencyId}/charges?limit=100`);
    document.getElementById("agencyChargesSub").textContent = `وكالة ${agencyName} (#${agencyId})`;
    const tb = document.querySelector("#agencyChargesTable tbody");
    tb.innerHTML = "";
    const rows = d.data || [];
    if (!rows.length) {
      tb.innerHTML = '<tr><td colspan="4" class="cell-muted">لا توجد شحنات مسجلة</td></tr>';
    } else {
      rows.forEach((x) => {
        const rec = x.recipient
          ? `${escapeHtml(x.recipient.name || "")} <span class="cell-muted">#${x.recipient.displayId ?? x.recipient.id}</span>`
          : "—";
        const snd = x.sender
          ? `${escapeHtml(x.sender.name || "")} <span class="cell-muted">#${x.sender.displayId ?? x.sender.id}</span>`
          : '<span class="cell-muted">—</span>';
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${rec}</td><td><strong>${x.amountCoins}</strong></td><td>${snd}</td><td><span class="cell-muted">${fmtDate(x.createdAt)}</span></td>`;
        tb.appendChild(tr);
      });
    }
    const total = d.pagination?.total ?? rows.length;
    document.getElementById("agencyChargesMeta").textContent = `إجمالي العمليات: ${total}`;
    document.getElementById("agencyChargesModal").classList.remove("hidden");
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to load charges"));
  }
};
window.closeAgencyChargesModal = function () {
  document.getElementById("agencyChargesModal").classList.add("hidden");
};

// App owner can inspect any agency's members and remove anyone (except the owner).
window.showAgencyMembers = async function (agencyId, agencyName) {
  try {
    const d = await apiFetch(`/admin-dashboard/agencies/${agencyId}/members`);
    const members = d.data || [];
    const box = document.getElementById("agencyMembersBox");
    const title = document.getElementById("agencyMembersTitle");
    title.textContent = `أعضاء وكالة ${agencyName} (#${agencyId})`;
    if (!members.length) {
      box.innerHTML = '<p class="cell-muted" style="padding:10px">لا يوجد أعضاء</p>';
    } else {
      box.innerHTML = members.map(m => {
        const earned = Number(m.earnedCoins ?? 0);
        const goal = Number(m.targetGoalCoins ?? 0);
        const remaining = Number(m.remainingCoins ?? 0);
        // #24: show the member's target so the owner can hold them accountable.
        const targetLabel = goal > 0
          ? `<span class="cell-muted">🎯 ${earned} / ${goal}${remaining > 0 ? ` (متبقٍ ${remaining})` : " ✓"}</span>`
          : `<span class="cell-muted">🎯 ${earned}</span>`;
        // Group 8: dollar value of earnings + join date.
        const dollars = m.dollars != null ? `<span class="cell-muted">💵 $${Number(m.dollars).toFixed(2)}</span>` : "";
        const joined = m.joinedAt ? `<span class="cell-muted">📅 ${fmtDate(m.joinedAt)}</span>` : "";
        // #19: level/VIP alongside target, editable via the same manual-override modal used in the users tab.
        const level = Number(m.user?.level ?? 1);
        const xp = Number(m.user?.xp ?? 0);
        const vip = Number(m.user?.vipLevel ?? 0);
        const progressionLabel = `<span class="cell-muted">Lv.${level} · VIP${vip}</span>`;
        return `
        <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;padding:8px;border-bottom:1px solid var(--card-border);">
          <div>
            <strong>${escapeHtml(m.user?.name ?? "")}</strong>
            <span class="cell-muted">#${m.user?.displayId ?? m.userId}</span>
            <span class="cell-muted">— ${m.role === "OWNER" ? "وكيل" : "مضيف"}</span>
            <div style="margin-top:2px;display:flex;gap:10px;flex-wrap:wrap">${targetLabel} ${progressionLabel} ${dollars} ${joined}</div>
          </div>
          <div style="display:flex;gap:6px;flex-shrink:0">
            <button class="btn-outline" onclick="openProgressionModal(${Number(m.userId)}, ${level}, ${xp}, ${vip})">المستوى/VIP</button>
            <button class="btn-outline" onclick="adminAdjustMemberTarget(${m.id}, ${agencyId}, '${escapeHtml(agencyName)}', 1)">+ تارجيت</button>
            <button class="btn-outline" onclick="adminAdjustMemberTarget(${m.id}, ${agencyId}, '${escapeHtml(agencyName)}', -1)">- تارجيت</button>
            ${m.role === "OWNER" ? "" : `<button class="btn-bad" onclick="adminRemoveAgencyMember(${m.id}, ${agencyId}, '${escapeHtml(agencyName)}')">إزالة (بدون رسوم)</button>`}
          </div>
        </div>`;
      }).join("");
    }
    document.getElementById("agencyMembersModal").classList.remove("hidden");
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// ------------------------------------------------------------
// B8 - "إضافة / خصم التارجيت" for one member.
//
// The dollar figure is NOT entered separately: a member's dollars are derived
// from their target through the تيرز التارجيت table, so moving the coins
// moves the dollars by construction and the two can never drift apart. That is
// the same proportional rule the client asked for on التبديل.
// ------------------------------------------------------------
window.adminAdjustMemberTarget = async function (memberId, agencyId, agencyName, sign) {
  const label = sign > 0 ? 'إضافة تارجيت' : 'خصم تارجيت';
  const raw = prompt(label + ' — الكمية بالكوينز:');
  if (raw == null) return;
  const amount = Math.floor(Number(raw));
  if (!Number.isFinite(amount) || amount <= 0) {
    showToast('❌ أدخل رقماً موجباً');
    return;
  }
  try {
    const d = await apiFetch(`/admin-dashboard/agency-members/${memberId}/target-adjust`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amountCoins: sign * amount }),
    });
    const after = (d && d.data) || {};
    showToast(`✓ ${label}: ${amount} — التارجيت الآن ${after.earnedCoins ?? '?'} ($${Number(after.dollars ?? 0).toFixed(2)})`);
    await showAgencyMembers(agencyId, agencyName);
  } catch (e) {
    showToast('❌ ' + e.message);
  }
};

window.closeAgencyMembersModal = function () {
  document.getElementById("agencyMembersModal").classList.add("hidden");
};

window.adminRemoveAgencyMember = async function (memberId, agencyId, agencyName) {
  openConfirmModal("إزالة عضو", "سيتم إخراج هذا العضو من الوكالة. متابعة؟", async () => {
    try {
      await apiFetch(`/admin-dashboard/agency-members/${memberId}`, { method: "DELETE" });
      showToast("✓ تمت إزالة العضو");
      await showAgencyMembers(agencyId, agencyName);
    } catch (e) {
      showToast("❌ خطأ: " + e.message);
    }
  });
};

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
  if (!shouldBan) {
    // Unban directly.
    await new Promise((resolve) => openConfirmModal("فك الحظر", "تأكيد فك الحظر عن المستخدم؟", async () => {
      await apiFetch(`/admin-dashboard/users/${userId}/ban`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ isBanned: false }),
      });
      resolve();
    }));
    showToast("✓ تم فك الحظر");
    await loadUsers();
    return;
  }
  // Ban: open modal to pick duration + reason.
  openBanModal(userId);
};

window.openBanModal = async function (userId) {
  selectedUserId = userId;
  document.getElementById("banReason").value = "";

  // Regular admins may only ban up to 3 days (#22) — hide the longer
  // options rather than let the request round-trip and 403.
  const isSuper = await ensureAdminRoleKnown();
  const sel = document.getElementById("banDuration");
  for (const opt of sel.options) {
    const longDuration = opt.value === "1m" || opt.value === "1y" || opt.value === "permanent";
    opt.disabled = longDuration && !isSuper;
  }
  document.getElementById("banDuration").value = isSuper ? "permanent" : "3d";

  document.getElementById("banModal").classList.remove("hidden");
};

window.closeBanModal = function () {
  selectedUserId = null;
  document.getElementById("banModal").classList.add("hidden");
};

window.confirmBan = async function () {
  try {
    if (!selectedUserId) return showToast("❗ اختر مستخدماً أولاً");
    const reason = document.getElementById("banReason").value.trim();
    const duration = document.getElementById("banDuration").value;
    if (!reason) return showToast("❗ سبب الحظر مطلوب");
    await apiFetch(`/admin-dashboard/users/${selectedUserId}/ban`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ isBanned: true, reason, duration }),
    });
    showToast("✓ تم حظر المستخدم");
    closeBanModal();
    await loadUsers();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to ban"));
  }
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


// ------------------------------------------------------------
// B9 - "أعلى المستويات": per-account counter reset.
//
// The client tests by gifting heavily and would otherwise sit at #1 forever,
// which discourages the real supporters. Resetting stamps a timestamp on the
// account; the board then counts only what it gifts AFTER that moment, so the
// account drops off and climbs back at whatever it genuinely earns. Nothing is
// deleted and the reset can be undone from the same button.
// ------------------------------------------------------------
async function loadTopSupporters() {
  const d = await apiFetch('/admin-dashboard/top-supporters?limit=50');
  const tb = document.querySelector('#topSupportersTable tbody');
  if (!tb) return;
  tb.innerHTML = '';
  (d.data || []).forEach((row) => {
    const u = row.user || {};
    const isReset = !!u.supportersResetAt;
    const tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + row.rank + '</td>' +
      '<td>' + escapeHtml(u.name || ('#' + (u.id || ''))) + '</td>' +
      '<td>' + escapeHtml(String(u.displayId ?? u.id ?? '')) + '</td>' +
      '<td>' + escapeHtml(String(row.coins ?? 0)) + '</td>' +
      '<td>' + (isReset ? 'مُصفّر منذ ' + fmtDate(u.supportersResetAt) : 'طبيعي') + '</td>' +
      '<td><button class="btn btn-outline" onclick="resetSupporterCounter(' + (u.id || 0) + ', ' + (isReset ? 'true' : 'false') + ')">' +
        (isReset ? 'إلغاء التصفير' : 'تصفير العداد') +
      '</button></td>';
    tb.appendChild(tr);
  });
}

async function resetSupporterCounter(userId, undo) {
  if (!userId) return;
  const msg = undo
    ? 'إرجاع كل سجل الدعم إلى القائمة؟'
    : 'تصفير عداد هذا الحساب؟ لن يُحذف أي سجل — سيُحتسب فقط ما يدعمه من الآن.';
  if (!confirm(msg)) return;
  await apiFetch('/admin-dashboard/users/' + userId + '/reset-supporter-counter', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ undo: !!undo }),
  });
  showToast(undo ? '✓ تم إلغاء التصفير' : '✓ تم تصفير العداد');
  await loadTopSupporters();
}
window.resetSupporterCounter = resetSupporterCounter;

async function loadAdvanced() { await Promise.all([loadTransactions(), loadTopups(), loadReports(), loadAnalytics(), loadQuests(), loadLeaderboard()]); }

// --- PRODUCTS (group 9: App Store + Private Store) ---
const PRODUCT_TYPE_LABELS = {
  ENTRANCE_EFFECT: "مركبة",
  ENTRANCE_BANNER: "مدخل",
  FRAME: "إطار",
  PROFILE_FRAME: "إطار",
  BADGE: "شارة",
  CHAT_BUBBLE: "فقاعة دردشة",
  background: "خلفية",
  ROOM_THEME: "خلفية",
};

function renderProductRow(p, isPrivate) {
  const isVideo = /\.(mp4|webm|mov)(\?|$)/i.test(p.file_url || "");
  const preview = isVideo
    ? `<a class="td-link" href="${p.file_url}" target="_blank">▶ تشغيل</a>`
    : p.file_url
      ? `<img src="${p.file_url}" width="44" height="44" style="border-radius:8px;object-fit:cover;" />`
      : "—";
  const safeName = escapeHtml(p.name || "").replace(/'/g, "\\'");
  const moveBtn = isPrivate
    ? `<button class="btn-ghost-sm" onclick="setProductPrivacy('${p.id}', false)">نقل للتطبيق</button>`
    : `<button class="btn-ghost-sm" onclick="setProductPrivacy('${p.id}', true)">نقل للخاص</button>`;
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td><span class="cell-id">${p.id}</span></td>
    <td>${escapeHtml(p.name)}${p.grant_to_all ? ' <span class="cell-muted">• لجميع المستخدمين</span>' : ''}</td>
    <td><span class="cell-muted">${PRODUCT_TYPE_LABELS[p.type] || p.type}</span></td>
    <td><strong>${p.price_coins}</strong></td>
    <td>${p.duration_days ? `${p.duration_days} يوم` : '<span class="cell-muted">أبدي</span>'}</td>
    <td>${preview}</td>
    <td>
      <div class="td-actions">
        <button class="btn-ok" onclick="openGrantItemModal('${p.id}', '${safeName}')">منح</button>
        <button class="btn-ghost-sm" onclick="openEditProductModal('${p.id}')">تعديل</button>
        ${moveBtn}
        <button class="btn-bad" onclick="deleteProduct('${p.id}')">حذف</button>
      </div>
    </td>
  `;
  return tr;
}

window.loadProducts = async function () {
  try {
    // Dashboard list includes private-store items; fall back to the public
    // endpoint if the backend hasn't been redeployed yet.
    const d = await apiFetchAny(["/admin-products/products", "/store/products"]);
    const appBody = document.querySelector("#productsTable tbody");
    const privBody = document.querySelector("#privateProductsTable tbody");
    appBody.innerHTML = "";
    if (privBody) privBody.innerHTML = "";

    const rows = d.data || d.products || [];
    // Kept so the edit modal opens pre-filled without a second round-trip.
    lastProductsById = {};
    for (const p of rows) lastProductsById[p.id] = p;
    for (const p of rows) {
      if (p.is_private && privBody) {
        privBody.appendChild(renderProductRow(p, true));
      } else {
        appBody.appendChild(renderProductRow(p, false));
      }
    }
    if (privBody && !privBody.children.length) {
      privBody.innerHTML = '<tr><td colspan="7" class="cell-muted">لا توجد منتجات خاصة</td></tr>';
    }
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.setProductPrivacy = async function (id, isPrivate) {
  try {
    await apiFetch("/admin-products/products/" + id, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ is_private: isPrivate }),
    });
    showToast(isPrivate ? "✓ نُقل إلى المتجر الخاص" : "✓ نُقل إلى متجر التطبيق");
    await loadProducts();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// Grant an item — either to one user by 6-digit display ID, or to everyone.
// The term always comes from the product itself (المدة المحددة في اللوحة).
let grantItemId = null;
let grantScope = "user";
let lastProductsById = {};

function durationLabel(p) {
  return p && p.duration_days ? `${p.duration_days} يوم` : "أبدي";
}

window.setGrantScope = function (scope) {
  grantScope = scope === "all" ? "all" : "user";
  const allBtn = document.getElementById("grantScopeAllBtn");
  const userBtn = document.getElementById("grantScopeUserBtn");
  const isAll = grantScope === "all";
  if (allBtn) allBtn.className = isAll ? "btn btn-primary" : "btn btn-outline";
  if (userBtn) userBtn.className = isAll ? "btn btn-outline" : "btn btn-primary";
  const box = document.getElementById("grantUserBox");
  if (box) box.style.display = isAll ? "none" : "";
  const hint = document.getElementById("grantScopeHint");
  const p = lastProductsById[grantItemId];
  if (hint) {
    hint.textContent = isAll
      ? `سيُمنح لكل مستخدمي البرنامج بمدة ${durationLabel(p)}، وكل من يسجّل لاحقاً يستلمه تلقائياً.`
      : `سيُمنح للمستخدم المحدد بمدة ${durationLabel(p)}.`;
  }
};

window.openGrantItemModal = function (itemId, itemName) {
  grantItemId = itemId;
  document.getElementById("grantItemSub").textContent = itemName || "";
  document.getElementById("grantDisplayId").value = "";
  setGrantScope("user");
  document.getElementById("grantItemModal").classList.remove("hidden");
};
window.closeGrantItemModal = function () {
  grantItemId = null;
  document.getElementById("grantItemModal").classList.add("hidden");
};
window.confirmGrantItem = async function () {
  try {
    if (!grantItemId) return;
    const body = { itemId: grantItemId, scope: grantScope };
    if (grantScope === "all") {
      if (!confirm("منح هذا المنتج لجميع مستخدمي البرنامج؟")) return;
    } else {
      const displayId = Number(document.getElementById("grantDisplayId").value);
      if (!displayId) return showToast("❗ أدخل Display ID صحيحاً");
      body.displayId = displayId;
    }
    const d = await apiFetch("/admin-products/grant", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast(`✓ ${d.message || "تم منح المنتج"} ${d.user?.name ? "— " + d.user.name : ""}`);
    closeGrantItemModal();
    await loadProducts();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to grant item"));
  }
};

// Edit a product — mainly the term in days, since items uploaded before
// durations existed have none.
let editProductId = null;
window.openEditProductModal = function (itemId) {
  const p = lastProductsById[itemId];
  // Without the cached row the form would open blank and a save would wipe the
  // name and zero the price. Reload instead of showing an empty form.
  if (!p) {
    showToast("❗ أعد تحميل قائمة المنتجات ثم حاول مرة أخرى");
    return;
  }
  editProductId = itemId;
  document.getElementById("editProductSub").textContent = p ? p.name : "";
  document.getElementById("editProductName").value = p?.name ?? "";
  document.getElementById("editProductPrice").value = p?.price_coins ?? 0;
  document.getElementById("editProductDuration").value = p?.duration_days ?? "";
  document.getElementById("editProductModal").classList.remove("hidden");
};
window.closeEditProductModal = function () {
  editProductId = null;
  document.getElementById("editProductModal").classList.add("hidden");
};
window.setEditProductDuration = function (days) {
  document.getElementById("editProductDuration").value = days ? String(days) : "";
};
window.confirmEditProduct = async function () {
  try {
    if (!editProductId) return;
    const name = document.getElementById("editProductName").value.trim();
    const price = document.getElementById("editProductPrice").value;
    const duration = document.getElementById("editProductDuration").value;
    await apiFetch("/admin-products/products/" + editProductId, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name,
        price_coins: price,
        // فارغ أو 0 = أبدي
        duration_days: String(duration).trim() === "" ? 0 : Number(duration),
      }),
    });
    showToast("✓ تم تحديث المنتج");
    closeEditProductModal();
    await loadProducts();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update product"));
  }
};

window.deleteProduct = async function (id) {
  if (!confirm("هل أنت متأكد من حذف المنتج؟")) return;
  try {
    await apiFetch("/admin/products/" + id, {
      method: "DELETE",
    });
    showToast("✓ تم حذف المنتج");
    await loadProducts();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// Duration chips: one tap fills the day box and clears أبدي.
window.setProductDuration = function (days) {
  const box = document.getElementById("p_duration");
  const perm = document.getElementById("p_permanent");
  if (box) box.value = days;
  if (perm) perm.checked = false;
  if (box) box.disabled = false;
};

// أبدي and a day count are mutually exclusive — ticking أبدي empties the box.
window.togglePermanent = function () {
  const box = document.getElementById("p_duration");
  const perm = document.getElementById("p_permanent");
  if (!box || !perm) return;
  box.disabled = perm.checked;
  if (perm.checked) box.value = "";
};

// ============================================================
// المربع الفارغ بالداخل (inner box) — where a decorated product lets the app
// draw. Sent to the API as fractions (0..0.49 per side); the dashboard takes
// them as percentages because that is what a human can eyeball off the artwork.
// ============================================================

/** Types whose artwork encloses app-drawn content and therefore needs a box. */
const INNER_BOX_TYPES = new Set([
  "chat_bubble", "entrance", "avatar_frame", "frame", "chat_top_banner", "profile_decor",
]);

function innerBoxSide(id) {
  const raw = document.getElementById(id)?.value;
  if (raw === undefined || String(raw).trim() === "") return 0;
  const pct = Number(raw);
  if (!Number.isFinite(pct) || pct <= 0) return 0;
  return Math.min(0.49, pct / 100);
}

/** null when nothing was entered, so the app keeps its built-in defaults. */
function readInnerBoxMeta() {
  const insets = {
    l: innerBoxSide("p_inset_l"),
    t: innerBoxSide("p_inset_t"),
    r: innerBoxSide("p_inset_r"),
    b: innerBoxSide("p_inset_b"),
  };
  if (!insets.l && !insets.t && !insets.r && !insets.b) return null;
  // The same box doubles as the 9-slice centre: everything outside it is
  // decoration and must never be stretched.
  return { insets, slice: insets };
}

/** Show the editor only for types that actually enclose content. */
window.syncInnerBoxEditor = function () {
  const type = document.getElementById("p_type")?.value;
  const box = document.getElementById("innerBoxEditor");
  if (box) box.style.display = INNER_BOX_TYPES.has(type) ? "flex" : "none";
};

/** Draws the configured box over the chosen file so it can be eyeballed. */
window.previewInnerBox = function () {
  const file = document.getElementById("p_file")?.files?.[0];
  const wrap = document.getElementById("innerBoxPreview");
  const img = document.getElementById("innerBoxImg");
  const rect = document.getElementById("innerBoxRect");
  if (!file || !file.type.startsWith("image/")) {
    return showToast("❗ اختر صورة أولاً لمعاينة المربع");
  }
  img.src = URL.createObjectURL(file);
  wrap.style.display = "block";
  const meta = readInnerBoxMeta() || { insets: { l: 0, t: 0, r: 0, b: 0 } };
  rect.style.left   = (meta.insets.l * 100) + "%";
  rect.style.top    = (meta.insets.t * 100) + "%";
  rect.style.right  = (meta.insets.r * 100) + "%";
  rect.style.bottom = (meta.insets.b * 100) + "%";
};

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("p_type")?.addEventListener("change", window.syncInnerBoxEditor);
  window.syncInnerBoxEditor();
});

window.addProduct = async function () {
  try {
    const fileInput = document.getElementById("p_file");
    const file = fileInput.files[0];
    if (!file) return showToast("❗ اختر ملفاً أولاً");

    const permanent = document.getElementById("p_permanent")?.checked;
    const durationDays = document.getElementById("p_duration")?.value;
    if (!permanent && !durationDays) {
      return showToast("❗ حدد مدة المنتج بالأيام أو اختر أبدي");
    }

    const formData = new FormData();
    formData.append("name",        document.getElementById("p_name").value);
    formData.append("type",        document.getElementById("p_type").value);
    formData.append("price_coins", document.getElementById("p_price").value);
    formData.append("is_private",  document.getElementById("p_private")?.checked ? "true" : "false");
    formData.append("is_permanent", permanent ? "true" : "false");
    formData.append("duration_days", permanent ? "" : String(durationDays || ""));
    const layoutMeta = readInnerBoxMeta();
    if (layoutMeta) formData.append("meta", JSON.stringify(layoutMeta));
    formData.append("file", file);

    await apiFetch("/admin-products/products", {
      method: "POST",
      body: formData,
    });

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
    // Gift ids are cuid strings — they must be quoted in the onclick handlers,
    // and the API fields are iconUrl/coinCost (not imageUrl/coinsValue).
    tr.innerHTML = `
      <td>${g.id}</td>
      <td>${escapeHtml(g.nameAr || g.name)}${g.cpEligible ? ' <span title="تحتسب ضمن CP">⚡CP</span>' : ''}</td>
      <td>${
        normalizeGiftImageUrl(g.iconUrl)
          ? `<img src="${normalizeGiftImageUrl(g.iconUrl)}" width="44" height="44" style="border-radius:8px;object-fit:cover;" />`
          : '<span class="cell-muted">—</span>'
      }</td>
      <td>${g.coinCost ?? 0}</td>
      <td>${g.sortOrder ?? 0}</td>
      <td>${g.isActive ? "✅" : "⛔"}</td>
      <td>
        <button class="btn btn-outline" onclick="openGiftModal('${g.id}')">تعديل</button>
        <button class="btn-bad" onclick="removeGift('${g.id}')">حذف</button>
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

window.uploadGiftVideo = async function () {
  const fileInput = document.getElementById("gift_videoFile");
  const file = fileInput?.files?.[0];
  if (!file) return showToast("اختر ملف فيديو من الجهاز أولاً");

  const formData = new FormData();
  formData.append("video", file);

  const d = await apiFetch("/upload/video", { method: "POST", body: formData });
  const videoUrl = d?.url || d?.imageUrl;
  if (!videoUrl) throw new Error("لم يتم إرجاع رابط الفيديو");

  document.getElementById("gift_animationUrl").value = videoUrl;
  // The server probes the clip; store its real length so the app plays the whole
  // video instead of cutting it at the 3 ثانية default.
  if (d?.durationMs) document.getElementById("gift_animationMs").value = String(d.durationMs);
  document.getElementById("gift_videoHasAlpha").value = d?.hasAlpha ? "1" : "0";

  const info = document.getElementById("giftVideoInfo");
  if (info) {
    const secs = d?.durationMs ? (d.durationMs / 1000).toFixed(1) : "?";
    info.textContent = `🎬 فيديو: ${secs} ث · ${d?.resolution || ""}${d?.hasAlpha ? " · خلفية شفافة" : ""}`;
    info.style.display = "block";
  }
  showToast("✓ تم رفع فيديو الهدية");
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
    const gift = (d.data || d.gifts || []).find((g) => String(g.id) === String(id));
    if (!gift) throw new Error('الهدية غير موجودة');
    idInput.value = String(gift.id);
    document.getElementById('gift_nameAr').value = gift.nameAr || gift.name || '';
    document.getElementById('gift_imageUrl').value = gift.iconUrl || '';
    document.getElementById('gift_animationUrl').value = gift.animationUrl || '';
    document.getElementById('gift_animationMs').value = gift.animationMs ?? '';
    document.getElementById('gift_videoHasAlpha').value = gift.videoHasAlpha ? '1' : '0';
    const info = document.getElementById('giftVideoInfo');
    if (info) {
      if (gift.animationUrl) {
        info.textContent = `🎬 فيديو مرفوع · ${((gift.animationMs ?? 3000) / 1000).toFixed(1)} ث`;
        info.style.display = 'block';
      } else {
        info.style.display = 'none';
      }
    }
    document.getElementById('gift_coinsValue').value = gift.coinCost ?? 0;
    document.getElementById('gift_sortOrder').value = gift.sortOrder ?? 0;
    document.getElementById('gift_isActive').checked = Boolean(gift.isActive);
    document.getElementById('gift_cpEligible').checked = Boolean(gift.cpEligible);
    document.getElementById('gift_tier').value = gift.tier || 'SMALL';
    const preview = document.getElementById("giftImagePreview");
    const safeGiftImage = normalizeGiftImageUrl(gift.iconUrl);
    if (safeGiftImage) {
      preview.src = safeGiftImage;
      preview.style.display = "block";
    } else {
      preview.style.display = "none";
    }
  } else {
    document.getElementById('gift_isActive').checked = true;
    document.getElementById('gift_cpEligible').checked = false;
    document.getElementById("giftImagePreview").style.display = "none";
    const info = document.getElementById('giftVideoInfo');
    if (info) info.style.display = 'none';
  }
  document.getElementById("gift_imageFile").value = "";
  document.getElementById("gift_videoFile").value = "";

  modal.classList.remove('hidden');
};

window.closeGiftModal = function () {
  document.getElementById('giftModal').classList.add('hidden');
};

window.saveGift = async function () {
  const id = document.getElementById('gift_id').value.trim();
  const coinsValue = Number(document.getElementById('gift_coinsValue').value || 0);
  // #14-16: tier and sortOrder are no longer admin-picked — derive a sensible
  // default from the coin value so the simple form stays just image/video/coins.
  const tierField = document.getElementById('gift_tier').value;
  const autoTier = coinsValue >= 5000 ? 'LEGENDARY' : coinsValue >= 1000 ? 'LARGE' : coinsValue >= 200 ? 'MEDIUM' : 'SMALL';
  // Server field names: iconUrl + coinCost (the old imageUrl/coinsValue names
  // were silently rejected by the API — gifts could never be saved).
  const payload = {
    nameAr: document.getElementById('gift_nameAr').value.trim(),
    iconUrl: document.getElementById('gift_imageUrl').value.trim(),
    animationUrl: document.getElementById('gift_animationUrl').value.trim() || null,
    coinCost: coinsValue,
    sortOrder: Number(document.getElementById('gift_sortOrder').value || 0),
    isActive: document.getElementById('gift_isActive').checked,
    cpEligible: document.getElementById('gift_cpEligible').checked,
    tier: tierField || autoTier,
  };
  // Video gifts play their clip on send; image gifts use the flying-image animation.
  payload.format = payload.animationUrl ? 'VIDEO' : 'SVG_CSS';
  if (payload.animationUrl) {
    const ms = Number(document.getElementById('gift_animationMs').value || 0);
    if (ms > 0) payload.animationMs = ms;
    payload.videoHasAlpha = document.getElementById('gift_videoHasAlpha').value === '1';
  }

  if (!payload.nameAr || !payload.iconUrl || payload.coinCost <= 0) {
    return showToast('❗ الاسم والصورة والقيمة بالكوينز مطلوبة');
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

// Only "مركبة (تأثير الدخول)" (seat_effect / ENTRANCE_EFFECT) is actually a
// video asset. Every other type — entrance banner, frame, badge, chat bubble,
// room background — is a static image; they were incorrectly forced to
// accept=video/* here, which made it impossible to pick an image file for
// them even though the backend already validates them as images.
typeSelect.addEventListener("change", () => {
  if (typeSelect.value === "seat_effect") {
    p_fileInput.accept        = "video/*";
    fileLabelText.textContent = "اختر ملف الفيديو";
  } else {
    p_fileInput.accept        = "image/*";
    fileLabelText.textContent = "اختر صورة";
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

let coinsMode = 'add';

function genderLabel(g) {
  const v = String(g || '').toLowerCase();
  if (v === 'male') return 'ذكر';
  if (v === 'female') return 'أنثى';
  if (v === 'other') return 'آخر';
  return '—';
}

window.openCoinsModal = function (userId, mode = 'add') {
  selectedUserId = userId;
  coinsMode = mode === 'remove' ? 'remove' : 'add';
  document.getElementById("coinsAmount").value = "";
  const titleEl = document.getElementById("coinsModalTitle");
  if (titleEl) titleEl.textContent = coinsMode === 'remove' ? "خصم كوينز" : "إضافة كوينز";
  document.getElementById("coinsModal").classList.remove("hidden");
};

window.closeCoinsModal = function () {
  selectedUserId = null;
  document.getElementById("coinsModal").classList.add("hidden");
};

window.confirmAddCoins = async function () {
  try {
    const amount = Number(document.getElementById("coinsAmount").value);
    if (!selectedUserId) return showToast("❗ اختر مستخدماً أولاً");
    if (!Number.isFinite(amount) || amount <= 0) return showToast("❗ أدخل رقماً صحيحاً");

    const action = coinsMode === 'remove' ? 'remove' : 'add';
    await apiFetchAny([
      `/admin/users/${selectedUserId}/coins/${action}`,
      `/api/v1/admin/users/${selectedUserId}/coins/${action}`,
    ], "POST", { amount });

    showToast(action === 'remove' ? "✓ تم خصم الكوينز بنجاح" : "✓ تم إضافة الكوينز بنجاح");
    closeCoinsModal();
    await loadUsers();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update coins"));
  }
};

// --- Target tiers (coins <-> dollars) ---
window.loadTargetTiers = async function () {
  try {
    const d = await apiFetch('/admin-dashboard/target-tiers');
    const tb = document.querySelector('#targetTiersTable tbody');
    if (!tb) return;
    tb.innerHTML = '';
    (d.data || []).forEach((t) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${t.id}</td>
        <td>${escapeHtml(String(t.coins))}</td>
        <td>$${escapeHtml(String(t.dollars))}</td>
        <td><div class="td-actions">
          <button class="btn-outline" onclick="editTargetTier(${t.id}, ${t.coins}, ${t.dollars})">تعديل</button>
          <button class="btn-bad" onclick="deleteTargetTier(${t.id})">حذف</button>
        </div></td>`;
      tb.appendChild(tr);
    });
  } catch (e) { showToast('❌ ' + (e?.message || 'فشل التحميل')); }
};

window.addTargetTier = async function () {
  try {
    const coins = Number(document.getElementById('tierCoins').value);
    const dollars = Number(document.getElementById('tierDollars').value);
    if (!Number.isFinite(coins) || coins <= 0) return showToast('❗ عدد كوينز صحيح مطلوب');
    if (!Number.isFinite(dollars) || dollars < 0) return showToast('❗ قيمة دولار صحيحة مطلوبة');
    await apiFetch('/admin-dashboard/target-tiers', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ coins, dollars }) });
    document.getElementById('tierCoins').value = '';
    document.getElementById('tierDollars').value = '';
    showToast('✓ تم إضافة التارجت');
    await loadTargetTiers();
  } catch (e) { showToast('❌ ' + (e?.message || 'فشل')); }
};

window.editTargetTier = async function (id, coins, dollars) {
  const newCoins = prompt('عدد الكوينز', coins);
  if (newCoins === null) return;

  // Raising or lowering the coins now moves the dollar figure with it, at this
  // tier's own rate, instead of leaving the admin to recompute it by hand.
  // Still editable — the suggestion is pre-filled, not forced.
  const rate = Number(coins) > 0 ? Number(dollars) / Number(coins) : 0;
  const suggested =
    rate > 0 && Number(newCoins) > 0
      ? Math.round(Number(newCoins) * rate * 100) / 100
      : dollars;

  const newDollars = prompt('الدولار (محسوب تلقائياً — يمكن تعديله)', suggested);
  if (newDollars === null) return;
  try {
    await apiFetch(`/admin-dashboard/target-tiers/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ coins: Number(newCoins), dollars: Number(newDollars) }) });
    showToast('✓ تم التعديل');
    await loadTargetTiers();
  } catch (e) { showToast('❌ ' + (e?.message || 'فشل')); }
};

window.deleteTargetTier = async function (id) {
  await new Promise((resolve) => openConfirmModal('حذف التارجت', 'تأكيد حذف هذا التارجت؟', async () => {
    await apiFetch(`/admin-dashboard/target-tiers/${id}`, { method: 'DELETE' });
    resolve();
  }));
  showToast('✓ تم الحذف');
  await loadTargetTiers();
};

// --- بيع/تبديل التارجيت: platform-wide freeze + per-account blocks ---
window.loadTargetSellPolicy = async function () {
  const statusEl = document.getElementById('targetSellStatus');
  try {
    const d = await apiFetch('/admin-dashboard/target-sell-policy');
    const blocked = !!(d.data && d.data.globallyBlocked);

    if (statusEl) {
      statusEl.textContent = blocked ? 'ممنوع — البيع والتبديل متوقفان' : 'مسموح — البيع والتبديل مفتوحان';
      statusEl.className = blocked ? 'badge badge-rejected' : 'badge badge-approved';
    }
    // Grey out the button for the state you are already in.
    const bBlock = document.getElementById('btnBlockTargetSell');
    const bUnblock = document.getElementById('btnUnblockTargetSell');
    if (bBlock) bBlock.disabled = blocked;
    if (bUnblock) bUnblock.disabled = !blocked;

    const tb = document.querySelector('#targetLocksTable tbody');
    if (tb) {
      tb.innerHTML = '';
      ((d.data && d.data.blockedUsers) || []).forEach((u) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${u.id}</td>
          <td>${escapeHtml(u.name || '')}</td>
          <td>${escapeHtml(String(u.displayId ?? '—'))}</td>
          <td><div class="td-actions">
            <button class="btn-outline" onclick="unlockUserTarget(${u.id})">فك المنع</button>
          </div></td>`;
        tb.appendChild(tr);
      });
    }
  } catch (e) {
    if (statusEl) {
      statusEl.textContent = 'تعذر التحميل';
      statusEl.className = 'badge badge-pending';
    }
    showToast('❌ ' + (e?.message || 'فشل تحميل حالة التارجيت'));
  }
};

window.setTargetSellPolicy = async function (blocked) {
  const title = blocked ? 'منع بيع وتبديل التارجيت' : 'فك المنع';
  const text = blocked
    ? 'سيتوقف بيع واستبدال التارجيت لكل المستخدمين حتى تقوم بفك المنع. متابعة؟'
    : 'سيُسمح لكل المستخدمين ببيع واستبدال التارجيت مرة أخرى. متابعة؟';

  await new Promise((resolve) => openConfirmModal(title, text, async () => {
    await apiFetch('/admin-dashboard/target-sell-policy', 'PATCH', { blocked });
    resolve();
  }));

  showToast(blocked ? '✓ تم منع بيع وتبديل التارجيت' : '✓ تم فك المنع');
  await loadTargetSellPolicy();
};

window.setUserTargetLock = async function (blocked) {
  try {
    const input = document.getElementById('targetLockUserId');
    const id = Number(input && input.value);
    if (!Number.isFinite(id) || id <= 0) return showToast('❗ أدخل رقم مستخدم صحيح');

    // The typed number is the ID shown on the profile (displayId); the server
    // resolves it. Name the account back so a typo is obvious instead of
    // silently blocking nobody.
    const r = await apiFetch(`/admin-dashboard/users/${id}/target-lock`, 'PATCH', { blocked });
    if (input) input.value = '';
    const who = r && r.data ? `${r.data.name || ''} #${r.data.displayId ?? r.data.userId}`.trim() : '';
    showToast((blocked ? '✓ تم منع الحساب ' : '✓ تم فك منع الحساب ') + who);
    await loadTargetSellPolicy();
  } catch (e) {
    showToast('❌ ' + (e?.message || 'فشل'));
  }
};

window.unlockUserTarget = async function (id) {
  try {
    // `by=id`: this comes from the blocked list, which carries the real row id —
    // no displayId guessing.
    await apiFetch(`/admin-dashboard/users/${id}/target-lock?by=id`, 'PATCH', { blocked: false });
    showToast('✓ تم فك منع الحساب');
    await loadTargetSellPolicy();
  } catch (e) {
    showToast('❌ ' + (e?.message || 'فشل'));
  }
};

// --- Edit profile (name + gender) ---
window.openEditProfileModal = function (userId, name, gender, nameLocked) {
  selectedUserId = userId;
  document.getElementById("editName").value = name || "";
  document.getElementById("editGender").value = String(gender || "").toLowerCase();
  document.getElementById("editNameLocked").checked = !!nameLocked;
  document.getElementById("editProfileModal").classList.remove("hidden");
};

window.closeEditProfileModal = function () {
  selectedUserId = null;
  document.getElementById("editProfileModal").classList.add("hidden");
};

window.confirmEditProfile = async function () {
  try {
    if (!selectedUserId) return showToast("❗ اختر مستخدماً أولاً");
    const name = document.getElementById("editName").value.trim();
    const gender = document.getElementById("editGender").value;
    const nameLocked = document.getElementById("editNameLocked").checked;
    const body = { nameLocked };
    if (name) body.name = name;
    if (gender) body.gender = gender;

    await apiFetch(`/admin-dashboard/users/${selectedUserId}/profile`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    showToast("✓ تم حفظ التعديلات");
    closeEditProfileModal();
    await loadUsers();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update profile"));
  }
};

// --- Manual override: level / xp / vipLevel (#12, #18) ---
window.openProgressionModal = function (userId, level, xp, vipLevel) {
  selectedUserId = userId;
  document.getElementById("progLevel").value = level ?? "";
  document.getElementById("progXp").value = xp ?? "";
  document.getElementById("progVip").value = vipLevel ?? "";
  document.getElementById("progressionModal").classList.remove("hidden");
};

window.closeProgressionModal = function () {
  selectedUserId = null;
  document.getElementById("progressionModal").classList.add("hidden");
};

window.confirmEditProgression = async function () {
  try {
    if (!selectedUserId) return showToast("❗ اختر مستخدماً أولاً");
    const body = {};
    const level = document.getElementById("progLevel").value;
    const xp = document.getElementById("progXp").value;
    const vip = document.getElementById("progVip").value;
    if (level !== "") body.level = Number(level);
    if (xp !== "") body.xp = Number(xp);
    if (vip !== "") body.vipLevel = Number(vip);
    if (Object.keys(body).length === 0) return showToast("❗ عدّل حقلاً واحداً على الأقل");

    await apiFetch(`/admin-dashboard/users/${selectedUserId}/progression`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    showToast("✓ تم حفظ المستوى/VIP");
    closeProgressionModal();
    await loadUsers();
  } catch (e) {
    showToast("❌ خطأ: " + (e?.message || "Failed to update progression"));
  }
};

// ============================================================
// EVENT LISTENERS
// ============================================================
document.getElementById("btnSave").addEventListener("click", () => {
  const normalized = normalizeApiBase(apiEl.value);
  apiEl.value = normalized;
  localStorage.setItem(LS_API, normalized);
  apiBaseText.textContent = normalized || "--";
  // sync settings input
  const settingsInput = document.getElementById("apiBaseSettings");
  if (settingsInput) settingsInput.value = normalized;
  showToast("✓ تم حفظ قاعدة الـ API");
});

document.getElementById("btnSaveSettings")?.addEventListener("click", () => {
  const normalized = normalizeApiBase(document.getElementById("apiBaseSettings").value);
  apiEl.value = normalized;
  localStorage.setItem(LS_API, normalized);
  apiBaseText.textContent = normalized || "--";
  const settingsInput = document.getElementById("apiBaseSettings");
  if (settingsInput) settingsInput.value = normalized;
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
document.getElementById("btnRoomSearch")?.addEventListener("click", async () => {
  try { await loadRooms(); } catch (e) { showToast("خطأ: " + e.message); }
});
document.getElementById("roomSearch")?.addEventListener("keydown", async (ev) => {
  if (ev.key === "Enter") { try { await loadRooms(); } catch (e) { showToast("خطأ: " + e.message); } }
});

document.getElementById("btnAgencies").addEventListener("click", async () => {
  try { await loadAgencies(); showToast("✓ تم تحميل الوكالات"); }     catch (e) { showToast("خطأ: " + e.message); }
});
document.getElementById("agencySearch")?.addEventListener("keydown", async (ev) => {
  if (ev.key === "Enter") { try { await loadAgencies(); } catch (e) { showToast("خطأ: " + e.message); } }
});
document.getElementById("agencyType")?.addEventListener("change", async () => {
  try { await loadAgencies(); } catch (e) { showToast("خطأ: " + e.message); }
});

document.getElementById("btnTransactions")?.addEventListener("click", () => loadTransactions().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnTopups")?.addEventListener("click", () => loadTopups().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnReports")?.addEventListener("click", () => loadReports().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAnalytics")?.addEventListener("click", () => loadAnalytics().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnLeaderboard")?.addEventListener("click", () => loadLeaderboard().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnTopSupporters")?.addEventListener("click", () => loadTopSupporters().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnBroadcast")?.addEventListener("click", () => sendBroadcast().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnQuests")?.addEventListener("click", () => loadQuests().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnQuestCreate")?.addEventListener("click", () => createQuest().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAdvancedRefresh")?.addEventListener("click", () => loadAdvanced().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnLoadGifts")?.addEventListener("click", () => loadGifts().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("giftSaveBtn")?.addEventListener("click", () => saveGift().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("giftUploadImageBtn")?.addEventListener("click", () => uploadGiftImage().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("giftUploadVideoBtn")?.addEventListener("click", () => uploadGiftVideo().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnAddGift")?.addEventListener("click", () => openGiftModal().catch(e => showToast("خطأ: " + e.message)));

// ============================================================
// ADMINS (#22, #23) — roster + role management (super-admin only mutates)
// ============================================================
let currentAdminIsSuper = null; // null = not yet known, else boolean

// Resolves currentAdminIsSuper once and caches it; safe to call from any
// section (ban modal, admins tab, ...) without depending on load order.
async function ensureAdminRoleKnown() {
  if (currentAdminIsSuper !== null) return currentAdminIsSuper;
  try {
    const me = await apiFetch("/admin-dashboard/me");
    currentAdminIsSuper = !!(me.data && me.data.isSuperAdmin);
  } catch { currentAdminIsSuper = false; }
  return currentAdminIsSuper;
}

async function loadAdmins() {
  // Learn the current dashboard user's own role to gate the controls.
  await ensureAdminRoleKnown();

  const note = document.getElementById("adminsSuperNote");
  if (note) note.style.display = currentAdminIsSuper ? "none" : "block";

  const d = await apiFetch("/admin-dashboard/admins");
  const rows = d.data || [];
  const tbody = document.querySelector("#adminsTable tbody");
  tbody.innerHTML = "";
  for (const a of rows) {
    const role = a.isSuperAdmin
      ? '<span class="badge badge-admin">سوبر أدمن</span>'
      : '<span class="badge">أدمن</span>';
    const did = Number(a.displayId || 0) >= 10000 ? `#${a.displayId}` : "—";
    let actions = "—";
    if (currentAdminIsSuper) {
      const superBtn = a.isSuperAdmin
        ? `<button class="btn-outline" onclick="setSuperAdmin(${a.id}, false)">إلغاء سوبر</button>`
        : `<button class="btn-ok" onclick="setSuperAdmin(${a.id}, true)">ترقية لسوبر</button>`;
      actions = `<div class="td-actions">${superBtn}
        <button class="btn-bad" onclick="revokeAdmin(${a.id})">إلغاء الأدمن</button></div>`;
    }
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${escapeHtml(a.id ?? "")}</span></td>
      <td><span class="cell-id">${escapeHtml(did)}</span></td>
      <td>${escapeHtml(a.name ?? "")}</td>
      <td>${role}</td>
      <td>${actions}</td>`;
    tbody.appendChild(tr);
  }
  document.getElementById("adminsMeta").textContent = `إجمالي المشرفين: ${rows.length}`;
}

async function grantAdmin() {
  const id = (document.getElementById("adminGrantId")?.value || "").trim();
  if (!id) return showToast("أدخل رقم المستخدم");
  await apiFetch(`/admin-dashboard/admins/${encodeURIComponent(id)}/grant`, "POST");
  document.getElementById("adminGrantId").value = "";
  showToast("✓ تم تعيين الأدمن");
  await loadAdmins();
}

async function revokeAdmin(userId) {
  if (!confirm("إلغاء صلاحية الأدمن عن هذا المستخدم؟")) return;
  try {
    await apiFetch(`/admin-dashboard/admins/${userId}/revoke`, "POST");
    showToast("✓ تم إلغاء الأدمن");
    await loadAdmins();
  } catch (e) { showToast("خطأ: " + e.message); }
}

async function setSuperAdmin(userId, value) {
  try {
    await apiFetch(`/admin-dashboard/admins/${userId}/super`, "PATCH", { value });
    showToast(value ? "✓ تمت الترقية لسوبر أدمن" : "✓ تم إلغاء السوبر أدمن");
    await loadAdmins();
  } catch (e) { showToast("خطأ: " + e.message); }
}
window.revokeAdmin = revokeAdmin;
window.setSuperAdmin = setSuperAdmin;

document.getElementById("btnAdmins")?.addEventListener("click", () => loadAdmins().catch(e => showToast("خطأ: " + e.message)));
document.getElementById("btnGrantAdmin")?.addEventListener("click", () => grantAdmin().catch(e => showToast("خطأ: " + e.message)));


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
// VIP LEVELS
// ============================================================
const VIP_BASE_STEP = 500000;
const VIP_MAX_LEVEL = 5;

// Group 10 state: all store items (app + private) and per-level reward selections.
let vipAllProducts = [];
const vipRewardSelections = {}; // level -> Set of item ids
let vipRewardsEditingLevel = null;

const VIP_REWARD_TYPE_LABELS = {
  BADGE: "شارة",
  FRAME: "إطار",
  PROFILE_FRAME: "إطار",
  ENTRANCE_BANNER: "مدخل",
  ENTRANCE_EFFECT: "مركبة",
  CHAT_BUBBLE: "فقاعة دردشة",
};

window.loadVipLevels = async function () {
  const tbody = document.querySelector("#vipTable tbody");
  if (!tbody) return;

  const [levelsRes, productsRes] = await Promise.all([
    apiFetchAny(["/admin-dashboard/vip-levels", "/admin/vip-levels"]),
    apiFetchAny(["/admin-products/products", "/store/products"]),
  ]);
  const saved = {};
  for (const c of levelsRes.data || []) saved[c.level] = c;
  vipAllProducts = productsRes.data || productsRes.products || [];
  const frames = vipAllProducts.filter(p => /frame/i.test(String(p.type || "")));

  // Render every configured level plus the 1..5 defaults, sorted.
  const levels = [...new Set([
    ...Array.from({ length: VIP_MAX_LEVEL }, (_, i) => i + 1),
    ...Object.keys(saved).map(Number),
  ])].sort((a, b) => a - b);

  tbody.innerHTML = "";
  for (const level of levels) {
    const c = saved[level] || {};
    vipRewardSelections[level] = new Set(c.rewardItemIds || []);
    const badge = normalizeGiftImageUrl(c.badgeUrl);
    const options = ['<option value="">— بدون إطار —</option>']
      .concat(frames.map(p =>
        `<option value="${p.id}" ${String(c.frameItemId) === String(p.id) ? "selected" : ""}>${escapeHtml(p.name)}</option>`))
      .join("");

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>VIP ${level}</strong></td>
      <td><input id="vip_name_${level}" class="form-input" style="max-width:140px" value="${escapeHtml(c.name || "VIP " + level)}" /></td>
      <td><input id="vip_threshold_${level}" type="number" class="form-input" style="max-width:160px" value="${c.threshold ?? level * VIP_BASE_STEP}" /></td>
      <td><input id="vip_price_${level}" type="number" min="0" class="form-input" style="max-width:140px"
                 placeholder="لا يُباع" value="${c.priceCoins ?? ""}" title="سعر شراء المستوى بالكوينز — فارغ = غير معروض للبيع" /></td>
      <td><input id="vip_duration_${level}" type="number" min="0" class="form-input" style="max-width:110px"
                 placeholder="أبدي" value="${c.durationDays ?? ""}" title="مدة المستوى المُشترى بالأيام — فارغ = أبدي" /></td>
      <td>
        <div style="display:flex;align-items:center;gap:8px;">
          <img id="vip_badge_preview_${level}" src="${badge}" width="40" height="40"
               style="border-radius:8px;object-fit:contain;${badge ? "" : "display:none;"}" />
          <input id="vip_badge_url_${level}" type="hidden" value="${escapeHtml(c.badgeUrl || "")}" />
          <input id="vip_badge_file_${level}" type="file" accept="image/*" style="display:none"
                 onchange="uploadVipBadge(${level})" />
          <button class="btn btn-outline" onclick="document.getElementById('vip_badge_file_${level}').click()">رفع الشارة</button>
        </div>
      </td>
      <td><select id="vip_frame_${level}" class="form-select" style="max-width:180px">${options}</select></td>
      <td style="text-align:center">
        <input id="vip_anim_avatar_${level}" type="checkbox" ${c.allowAnimatedAvatar ? "checked" : ""}
               title="الصورة الشخصية المتحركة (GIF). أقل مستوى مُفعّل يمنح الخاصية له ولكل ما فوقه." />
      </td>
      <td><button class="btn btn-outline" id="vip_rewards_btn_${level}" onclick="openVipRewardsModal(${level})">🎁 منتجات (${vipRewardSelections[level].size})</button></td>
      <td><button class="btn btn-primary" onclick="saveVipLevel(${level})">حفظ</button></td>
    `;
    tbody.appendChild(tr);
  }
};

// Add a brand-new tier: save level + required coins, then edit it in the table.
window.addVipTier = async function () {
  try {
    const level = Number(document.getElementById("newVipLevel").value);
    const threshold = Number(document.getElementById("newVipThreshold").value);
    if (!level || level < 1 || level > 100) return showToast("❗ رقم المستوى يجب أن يكون 1-100");
    if (!threshold || threshold < 1) return showToast("❗ أدخل عدد الكوينز المطلوبة");
    const priceCoins = Number(document.getElementById("newVipPrice")?.value || 0);
    const durationDays = Number(document.getElementById("newVipDuration")?.value || 0);
    await apiFetchAny(["/admin-dashboard/vip-levels", "/admin/vip-levels"], {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ level, name: `VIP ${level}`, threshold, priceCoins, durationDays }),
    });
    document.getElementById("newVipLevel").value = "";
    document.getElementById("newVipThreshold").value = "";
    if (document.getElementById("newVipPrice")) document.getElementById("newVipPrice").value = "";
    if (document.getElementById("newVipDuration")) document.getElementById("newVipDuration").value = "";
    showToast(`✓ تم إضافة مستوى VIP ${level}`);
    await loadVipLevels();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// Rewards picker: checkboxes over all store items (app + private), grouped by type.
window.openVipRewardsModal = function (level) {
  vipRewardsEditingLevel = level;
  const selected = vipRewardSelections[level] || new Set();
  document.getElementById("vipRewardsSub").textContent =
    `VIP ${level} — اختر الشارات/الإطارات/المداخل التي تُمنح تلقائياً (من متجر التطبيق أو الخاص)`;

  const groups = {};
  for (const p of vipAllProducts) {
    const label = VIP_REWARD_TYPE_LABELS[p.type] || p.type;
    (groups[label] = groups[label] || []).push(p);
  }

  const listEl = document.getElementById("vipRewardsList");
  listEl.innerHTML = Object.entries(groups).map(([label, items]) => `
    <div style="margin-bottom:10px">
      <div class="form-card-title" style="margin-bottom:4px">${escapeHtml(label)}</div>
      ${items.map(p => `
        <label style="display:flex;align-items:center;gap:8px;padding:4px 2px;cursor:pointer">
          <input type="checkbox" class="vip-reward-check" value="${p.id}" ${selected.has(p.id) ? "checked" : ""} />
          <span>${escapeHtml(p.name)}</span>
          <span class="cell-muted">${p.price_coins ?? 0} coins${p.is_private ? " · 🔒 خاص" : ""}</span>
        </label>`).join("")}
    </div>`).join("") || '<p class="cell-muted">لا توجد منتجات في المتجر — أضف منتجات أولاً</p>';

  document.getElementById("vipRewardsModal").classList.remove("hidden");
};

window.closeVipRewardsModal = function () {
  vipRewardsEditingLevel = null;
  document.getElementById("vipRewardsModal").classList.add("hidden");
};

window.confirmVipRewards = function () {
  const level = vipRewardsEditingLevel;
  if (level == null) return;
  const checked = [...document.querySelectorAll(".vip-reward-check:checked")].map(el => el.value);
  vipRewardSelections[level] = new Set(checked);
  const btn = document.getElementById(`vip_rewards_btn_${level}`);
  if (btn) btn.textContent = `🎁 منتجات (${checked.length})`;
  closeVipRewardsModal();
  showToast(`اختيار VIP ${level} جاهز — اضغط حفظ لتثبيته`);
};

window.uploadVipBadge = async function (level) {
  try {
    const file = document.getElementById(`vip_badge_file_${level}`)?.files?.[0];
    if (!file) return;
    const formData = new FormData();
    formData.append("image", file);
    const d = await apiFetch("/upload/image", { method: "POST", body: formData });
    const url = d?.url || d?.imageUrl;
    if (!url) throw new Error("لم يتم إرجاع رابط الصورة");
    document.getElementById(`vip_badge_url_${level}`).value = url;
    const preview = document.getElementById(`vip_badge_preview_${level}`);
    preview.src = normalizeGiftImageUrl(url);
    preview.style.display = "block";
    showToast(`✓ تم رفع شارة VIP ${level} — اضغط حفظ`);
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.saveVipLevel = async function (level) {
  try {
    const body = {
      level,
      name: document.getElementById(`vip_name_${level}`).value.trim() || `VIP ${level}`,
      threshold: Number(document.getElementById(`vip_threshold_${level}`).value || 0),
      badgeUrl: document.getElementById(`vip_badge_url_${level}`).value || undefined,
      frameItemId: document.getElementById(`vip_frame_${level}`).value || undefined,
      // Empty price = off sale, empty duration = the bought tier never expires.
      // Sent as 0 so the server stores null rather than leaving the old value.
      priceCoins: Number(document.getElementById(`vip_price_${level}`)?.value || 0),
      durationDays: Number(document.getElementById(`vip_duration_${level}`)?.value || 0),
      // Group 10: the multi-item grant list picked in the rewards modal.
      rewardItemIds: [...(vipRewardSelections[level] || new Set())],
      // A16: animated (GIF) profile photo. The server treats the LOWEST ticked
      // tier as the floor, so ticking VIP10 alone grants VIP10 and everything
      // above it - "VIP10 وما فوق".
      allowAnimatedAvatar: !!document.getElementById(`vip_anim_avatar_${level}`)?.checked,
    };
    await apiFetchAny(["/admin-dashboard/vip-levels", "/admin/vip-levels"], {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast(`✓ تم حفظ VIP ${level}`);
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// ============================================================
// LV LEVELS (مستويات LV) — the XP counterpart of the VIP tiers.
// A level with no saved threshold shows the built-in curve value
// ((level-1)^2 * 100) as a hint; nothing is applied until you press حفظ, so
// opening this page never changes anyone's level.
// ============================================================
const LV_DEFAULT_ROWS = 20;
const lvRewardSelections = {}; // level -> Set of item ids
let lvAllProducts = [];
let lvRewardsEditingLevel = null;

const lvFormulaThreshold = (level) => Math.pow(level - 1, 2) * 100;

window.loadLvLevels = async function () {
  const tbody = document.querySelector("#lvTable tbody");
  if (!tbody) return;

  const [levelsRes, productsRes] = await Promise.all([
    apiFetchAny(["/admin-dashboard/levels", "/admin/levels"]),
    apiFetchAny(["/admin-products/products", "/store/products"]),
  ]);
  const saved = {};
  for (const c of levelsRes.data || []) saved[c.level] = c;
  lvAllProducts = productsRes.data || productsRes.products || [];

  const levels = [...new Set([
    ...Array.from({ length: LV_DEFAULT_ROWS }, (_, i) => i + 1),
    ...Object.keys(saved).map(Number),
  ])].sort((a, b) => a - b);

  tbody.innerHTML = "";
  for (const level of levels) {
    const c = saved[level] || {};
    const isConfigured = c.threshold != null;
    lvRewardSelections[level] = new Set(c.rewardItemIds || []);
    const badge = normalizeGiftImageUrl(c.badgeUrl);

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>LV ${level}</strong>${isConfigured ? "" : ' <span class="settings-hint">(افتراضي)</span>'}</td>
      <td><input id="lv_name_${level}" class="form-input" style="max-width:140px" value="${escapeHtml(c.name || "LV " + level)}" /></td>
      <td><input id="lv_threshold_${level}" type="number" min="0" class="form-input" style="max-width:160px" value="${c.threshold ?? lvFormulaThreshold(level)}" /></td>
      <td>
        <div style="display:flex;align-items:center;gap:8px;">
          <img id="lv_badge_preview_${level}" src="${badge}" width="40" height="40"
               style="border-radius:8px;object-fit:contain;${badge ? "" : "display:none;"}" />
          <input id="lv_badge_url_${level}" type="hidden" value="${escapeHtml(c.badgeUrl || "")}" />
          <input id="lv_badge_file_${level}" type="file" accept="image/*" style="display:none"
                 onchange="uploadLvBadge(${level})" />
          <button class="btn btn-outline" onclick="document.getElementById('lv_badge_file_${level}').click()">رفع الشارة</button>
        </div>
      </td>
      <td><button class="btn btn-outline" id="lv_rewards_btn_${level}" onclick="openLvRewardsModal(${level})">🎁 منتجات (${lvRewardSelections[level].size})</button></td>
      <td>
        <button class="btn btn-primary" onclick="saveLvLevel(${level})">حفظ</button>
        ${isConfigured ? `<button class="btn btn-outline" onclick="backfillLvRewards(${level})" title="منح منتجات هذا المستوى لمن بلغه بالفعل">🎁 بأثر رجعي</button>` : ""}
        ${isConfigured ? `<button class="btn btn-outline" onclick="deleteLvLevel(${level})">إرجاع للافتراضي</button>` : ""}
      </td>
    `;
    tbody.appendChild(tr);
  }
};

window.addLvTier = async function () {
  try {
    const level = Number(document.getElementById("newLvLevel").value);
    const thresholdRaw = document.getElementById("newLvThreshold").value;
    const threshold = Number(thresholdRaw);
    if (!level || level < 1 || level > 100) return showToast("❗ رقم المستوى يجب أن يكون 1-100");
    if (thresholdRaw === "" || !Number.isFinite(threshold) || threshold < 0) {
      return showToast("❗ أدخل عدد الكوينزات المُهداة المطلوبة");
    }
    await apiFetchAny(["/admin-dashboard/levels", "/admin/levels"], {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ level, name: `LV ${level}`, threshold }),
    });
    document.getElementById("newLvLevel").value = "";
    document.getElementById("newLvThreshold").value = "";
    showToast(`✓ تم إضافة مستوى LV ${level}`);
    await loadLvLevels();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.openLvRewardsModal = function (level) {
  lvRewardsEditingLevel = level;
  const selected = lvRewardSelections[level] || new Set();
  document.getElementById("lvRewardsSub").textContent =
    `LV ${level} — اختر المنتجات التي تُمنح تلقائياً عند بلوغ هذا المستوى`;

  const groups = {};
  for (const p of lvAllProducts) {
    const label = VIP_REWARD_TYPE_LABELS[p.type] || p.type;
    (groups[label] = groups[label] || []).push(p);
  }

  const listEl = document.getElementById("lvRewardsList");
  listEl.innerHTML = Object.entries(groups).map(([label, items]) => `
    <div style="margin-bottom:10px">
      <div class="form-card-title" style="margin-bottom:4px">${escapeHtml(label)}</div>
      ${items.map(p => `
        <label style="display:flex;align-items:center;gap:8px;padding:4px 2px;cursor:pointer">
          <input type="checkbox" class="lv-reward-check" value="${p.id}" ${selected.has(p.id) ? "checked" : ""} />
          <span>${escapeHtml(p.name)}</span>
          <span class="cell-muted">${p.price_coins ?? 0} coins${p.is_private ? " · 🔒 خاص" : ""}</span>
        </label>`).join("")}
    </div>`).join("") || '<p class="cell-muted">لا توجد منتجات في المتجر — أضف منتجات أولاً</p>';

  document.getElementById("lvRewardsModal").classList.remove("hidden");
};

window.closeLvRewardsModal = function () {
  lvRewardsEditingLevel = null;
  document.getElementById("lvRewardsModal").classList.add("hidden");
};

window.confirmLvRewards = function () {
  const level = lvRewardsEditingLevel;
  if (level == null) return;
  const checked = [...document.querySelectorAll(".lv-reward-check:checked")].map(el => el.value);
  lvRewardSelections[level] = new Set(checked);
  const btn = document.getElementById(`lv_rewards_btn_${level}`);
  if (btn) btn.textContent = `🎁 منتجات (${checked.length})`;
  closeLvRewardsModal();
  showToast(`اختيار LV ${level} جاهز — اضغط حفظ لتثبيته`);
};

window.uploadLvBadge = async function (level) {
  try {
    const file = document.getElementById(`lv_badge_file_${level}`)?.files?.[0];
    if (!file) return;
    const formData = new FormData();
    formData.append("image", file);
    const d = await apiFetch("/upload/image", { method: "POST", body: formData });
    const url = d?.url || d?.imageUrl;
    if (!url) throw new Error("لم يتم إرجاع رابط الصورة");
    document.getElementById(`lv_badge_url_${level}`).value = url;
    const preview = document.getElementById(`lv_badge_preview_${level}`);
    preview.src = normalizeGiftImageUrl(url);
    preview.style.display = "block";
    showToast(`✓ تم رفع شارة LV ${level} — اضغط حفظ`);
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

window.saveLvLevel = async function (level) {
  try {
    const body = {
      level,
      name: document.getElementById(`lv_name_${level}`).value.trim() || `LV ${level}`,
      threshold: Number(document.getElementById(`lv_threshold_${level}`).value || 0),
      badgeUrl: document.getElementById(`lv_badge_url_${level}`).value || undefined,
      rewardItemIds: [...(lvRewardSelections[level] || new Set())],
    };
    await apiFetchAny(["/admin-dashboard/levels", "/admin/levels"], {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    showToast(`✓ تم حفظ LV ${level}`);
    await loadLvLevels();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// Retroactive grant: hands the configured items to users who are already at or
// above a tier. Safe to press repeatedly — the server skips existing grants and
// reports only what it actually created.
window.backfillLvRewards = async function (level) {
  const scope = level ? `المستوى LV ${level}` : "كل المستويات";
  if (!confirm(`منح منتجات ${scope} لكل المستخدمين الذين بلغوه بالفعل؟`)) return;
  try {
    const d = await apiFetchAny(["/admin-dashboard/levels/backfill", "/admin/levels/backfill"], {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(level ? { level } : {}),
    });
    const granted = d?.data?.grantedRows ?? 0;
    const users = d?.data?.usersAffected ?? 0;
    const details = d?.data?.details || [];
    showToast(granted > 0
      ? `✓ تم منح ${granted} منتج لـ ${users} مستخدم`
      : "لا يوجد جديد — الجميع لديه هذه المنتجات بالفعل");
    showLvBackfillDetails(details, granted, users, scope);
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

// Per-tier breakdown of what the backfill did. "مُنح فعلياً" is 0 when everyone
// eligible already owned the items — that is a success, not a failure.
window.showLvBackfillDetails = function (details, granted, users, scope) {
  const tbody = document.querySelector("#lvBackfillTable tbody");
  if (!tbody) return;

  document.getElementById("lvBackfillSub").textContent =
    `${scope} — ${granted} منتج مُنح لـ ${users} مستخدم`;

  tbody.innerHTML = details.length
    ? details.map(r => `
        <tr>
          <td><strong>LV ${Number(r.level)}</strong></td>
          <td>${Number(r.users || 0)}</td>
          <td>${Number(r.items || 0)}</td>
          <td>${Number(r.granted || 0) > 0
            ? `<strong>${Number(r.granted)}</strong>`
            : '<span class="cell-muted">0 — موجود مسبقاً</span>'}</td>
        </tr>`).join("")
    : '<tr><td colspan="4" class="cell-muted">لا توجد مستويات بمنتجات مُهيأة — أضف منتجات لمستوى ثم أعد المحاولة</td></tr>';

  document.getElementById("lvBackfillModal").classList.remove("hidden");
};

window.closeLvBackfillModal = function () {
  document.getElementById("lvBackfillModal").classList.add("hidden");
};

// Removing a tier hands that level back to the built-in curve.
window.deleteLvLevel = async function (level) {
  if (!confirm(`إرجاع LV ${level} إلى المعادلة الافتراضية؟`)) return;
  try {
    await apiFetchAny([`/admin-dashboard/levels/${level}`, `/admin/levels/${level}`], {
      method: "DELETE",
    });
    showToast(`✓ تم إرجاع LV ${level} للافتراضي`);
    await loadLvLevels();
  } catch (e) {
    showToast("❌ خطأ: " + e.message);
  }
};

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
  const raw = localStorage.getItem(LS_API) || "";
  const saved = normalizeApiBase(raw) || normalizeApiBase(apiEl.value) || getDefaultApiBase();
  if (saved && saved !== raw) localStorage.setItem(LS_API, saved);
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

  // ===================== CP / TARGET SETTINGS =====================
  window.loadCpSettings = async function () {
    try {
      const res = await apiFetch("/settings");
      const s = (res && res.data) || {};
      const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
      set("cpPerCoin", s.cp_per_coin ?? "1");
      set("cpTargetPerDollar", s.target_coins_per_dollar ?? "10000");
      set("cpLevelMultiplier", s.level_multiplier ?? "1.5");
    } catch (e) {
      showToast("تعذر تحميل إعدادات CP: " + e.message);
    }
  };

  window.saveCpSettings = async function () {
    try {
      const val = (id) => (document.getElementById(id) || {}).value;
      const body = {
        cp_per_coin: val("cpPerCoin") || "1",
        target_coins_per_dollar: val("cpTargetPerDollar") || "10000",
        level_multiplier: val("cpLevelMultiplier") || "1.5",
      };
      await apiFetchAny(["/admin-dashboard/settings", "/admin/settings"], "PATCH", body);
      showToast("تم حفظ إعدادات CP ✓");
      await window.loadCpSettings();
    } catch (e) {
      showToast("فشل الحفظ: " + e.message);
    }
  };
})();
