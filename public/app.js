/* ============================================================
   SMAFOX ADMIN DASHBOARD — app.js
   ============================================================ */

"use strict";

// ---- CONSTANTS ----
const LS_API = "sf_admin_dashboard_api";

// ---- DOM REFS ----
const apiEl          = document.getElementById("apiBase");
const apiBaseText    = document.getElementById("apiBaseText");
const authLabel      = document.getElementById("authLabel");
const authDot        = document.getElementById("authDot");
const toast          = document.getElementById("toast");

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

function getApiBase() {
  let base = apiEl.value.trim();
  if (base.endsWith("/")) base = base.slice(0, -1);
  return base;
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
    const res = await fetch(base + path, {
      ...opts,
      credentials: "include",
      headers: Object.assign({ Accept: "application/json" }, opts.headers || {}),
    });

    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }

    if (res.ok) return data;

    const msg = data && (data.message || data.error)
      ? (data.message || data.error)
      : `HTTP ${res.status}`;

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
async function apiFetch(path, opts = {}) {
  return fetchWithBaseFallback(path, opts);
}

// ============================================================
// AUTH
// ============================================================
async function doLogin(email, password) {
  return fetchWithBaseFallback("/admin-dashboard-auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, password }),
  });
}

async function doLogout() {
  await fetchWithBaseFallback("/admin-dashboard-auth/logout", {
    method: "POST",
    headers: { Accept: "application/json" },
  });
}

function setAuthState(online, label) {
  authDot.classList.toggle("online", online);
  authLabel.textContent = label;
}

async function checkAuth() {
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
  const q     = `?page=${encodeURIComponent(page)}&limit=${encodeURIComponent(limit)}`;

  const d     = await apiFetch("/admin-dashboard/users" + q);
  const tbody = document.querySelector("#usersTable tbody");
  tbody.innerHTML = "";

  const rows = d.data || [];
  for (const u of rows) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><span class="cell-id">${escapeHtml(u.id ?? "")}</span></td>
      <td>${escapeHtml(u.name ?? "")}</td>
      <td><span class="cell-muted">${escapeHtml(u.email ?? "")}</span></td>
      <td><span class="cell-muted">${escapeHtml(u.phone ?? "")}</span></td>
      <td><strong>${u.coinsBalance ?? u.coins ?? 0}</strong></td>
      <td>${u.isAdmin ? '<span class="badge badge-admin">أدمن</span>' : ""}</td>
      <td><span class="cell-muted">${fmtDate(u.createdAt)}</span></td>
      <td>
        <div class="td-actions">
          <button class="btn-ok" onclick="openCoinsModal('${escapeHtml(u.id ?? "")}')">
            + كوينز
          </button>
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
      <td><span class="cell-muted">${fmtDate(r.createdAt)}</span></td>
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
  } catch (e) {
    showToast("خطأ: " + e.message);
  }
}

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
          ${p.type === "PROFILE_FRAME"
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

// File input type switching
const typeSelect   = document.getElementById("p_type");
const fileLabelText = document.getElementById("fileLabelText");
const p_fileInput  = document.getElementById("p_file");

typeSelect.addEventListener("change", () => {
  if (typeSelect.value === "avatar_frame") {
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
    if (ok) loadAll().catch(e => showToast("خطأ: " + e.message));
  });
})();
