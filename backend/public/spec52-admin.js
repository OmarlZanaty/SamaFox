// ============================================================
// لوحة التحكم — صفحات تحديث 2026-10-20 (SPEC52)
//   الصلاحيات المالية (المالك) · وتُضاف هنا صفحات الصاروخ و PK وقوائم المتجر
// Uses apiFetch / showToast / escapeHtml from app.js. The server enforces
// every rule; hiding a button here is only a convenience.
// ============================================================
(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const esc = (s) => (typeof escapeHtml === "function" ? escapeHtml(String(s ?? "")) : String(s ?? ""));
  const toast = (m) => (typeof showToast === "function" ? showToast(m) : alert(m));
  const val = (id) => ($(id)?.value ?? "").trim();
  const dt = (d) => (d ? new Date(d).toLocaleString("en-GB") : "—");
  const n = (v) => Number(v || 0).toLocaleString("en-US");

  async function call(path, method, body) {
    try {
      return await apiFetch(path, method || "GET", body);
    } catch (e) {
      toast("❌ " + (e?.message || "فشل"));
      throw e;
    }
  }

  // ── capabilities: hide what this admin may not do ──────────────────────
  let caps = { isOwner: false, permissions: [] };
  window.spec52Caps = () => caps;
  window.spec52Can = (perm) => caps.isOwner || caps.permissions.includes(perm);

  async function loadCaps() {
    try {
      const r = await apiFetch("/admin-dashboard/me/capabilities", "GET");
      caps = r?.data || caps;
    } catch (_) {
      /* not logged in yet */
    }
    document.querySelectorAll("[data-owner-only]").forEach((el) => {
      el.style.display = caps.isOwner ? "" : "none";
    });
    document.querySelectorAll("[data-perm]").forEach((el) => {
      const ok = window.spec52Can(el.getAttribute("data-perm"));
      el.toggleAttribute("disabled", !ok);
      if (!ok) el.title = "هذه العملية تحتاج صلاحية من المالك";
    });
  }
  window.spec52LoadCaps = loadCaps;

  // ── الصلاحيات المالية ────────────────────────────────────────────────────
  let catalog = [];
  async function permsLoad() {
    await loadCaps();
    if (!caps.isOwner) {
      $("permsBody").innerHTML = '<p class="cell-muted">هذه الصفحة للمالك فقط.</p>';
      return;
    }
    const [c, g] = await Promise.all([call("/admin-dashboard/permissions/catalog"), call("/admin-dashboard/permissions/grants")]);
    catalog = c?.data || [];
    $("perm_key").innerHTML = catalog
      .filter((p) => p.delegable)
      .map((p) => `<option value="${esc(p.key)}">${esc(p.label)} (${esc(p.key)})</option>`)
      .join("");
    const label = (k) => catalog.find((p) => p.key === k)?.label || k;
    const rows = g?.data || [];
    $("permsTable").querySelector("tbody").innerHTML =
      rows
        .map(
          (r) => `<tr>
        <td>${r.id}</td>
        <td>${esc(r.user?.name || "")}<div class="cell-muted">ID ${esc(r.user?.displayId ?? r.userId)} · ${r.user?.isSuperAdmin ? "سوبر أدمن" : r.user?.isAdmin ? "أدمن" : "—"}</div></td>
        <td><strong>${esc(label(r.permission))}</strong><div class="cell-muted">${esc(r.permission)}</div></td>
        <td>${esc(r.grantedByUser?.name || r.grantedBy)}</td>
        <td>${dt(r.createdAt)}</td>
        <td>${r.revokedAt ? `<span class="badge badge-rejected">مسحوبة ${dt(r.revokedAt)}</span>` : '<span class="badge badge-approved">فعالة</span>'}</td>
        <td>${r.revokedAt ? "" : `<button class="btn btn-outline btn-sm" onclick="permsRevoke(${r.id})">سحب</button>`}</td>
      </tr>`,
        )
        .join("") || '<tr><td colspan="7" class="cell-muted">لا توجد صلاحيات ممنوحة — المالك وحده يملك كل الصلاحيات المالية</td></tr>';
  }

  async function permsGrant() {
    const raw = val("perm_user");
    if (!raw) return toast("اكتب رقم المشرف");
    // Accept the internal id or the public display id.
    let userId = Number(raw);
    try {
      const u = await apiFetch("/admin-dashboard/users?search=" + encodeURIComponent(raw), "GET");
      const list = u?.data?.users || u?.data || [];
      const hit = list.find((x) => String(x.displayId) === raw || String(x.id) === raw);
      if (hit) userId = Number(hit.id);
    } catch (_) {}
    await call("/admin-dashboard/permissions/grants", "POST", { userId, permission: val("perm_key") });
    toast("✅ تم منح الصلاحية");
    $("perm_user").value = "";
    permsLoad();
  }

  async function permsRevoke(id) {
    if (!confirm("سحب هذه الصلاحية؟")) return;
    await call(`/admin-dashboard/permissions/grants/${id}`, "DELETE");
    toast("✅ تم السحب");
    permsLoad();
  }

  Object.assign(window, { permsLoad, permsGrant, permsRevoke });

  // ── section router hook (called from app.js navigate) ───────────────────
  const loaders = { perms: permsLoad };
  window.spec52Register = (sec, fn) => {
    loaders[sec] = fn;
  };
  window.spec52Load = (sec) => {
    const fn = loaders[sec];
    if (fn) Promise.resolve(fn()).catch((e) => toast("خطأ: " + (e?.message || e)));
  };
  window.spec52Helpers = { $, esc, toast, val, dt, n, call };

  document.addEventListener("DOMContentLoaded", () => setTimeout(loadCaps, 800));
})();
