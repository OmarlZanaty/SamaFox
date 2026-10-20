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
  const imgUrl = (u) => (typeof normalizeGiftImageUrl === "function" ? normalizeGiftImageUrl(u) : u);

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

  // ── SPEC52 #38: قوائم الهدايا ────────────────────────────────────────────
  let glCats = [];
  let glGifts = [];
  const glSelected = new Set();

  async function giftListsLoad() {
    await loadCaps();
    const [c, g] = await Promise.all([
      call("/admin/gifts/categories?includeInactive=1"),
      apiFetchAny(["/admin-dashboard/gifts", "/admin/gifts"]),
    ]);
    glCats = c?.data || [];
    glGifts = g?.data || g?.gifts || [];
    const opts = (withNone) =>
      (withNone ? '<option value="">— بدون قائمة (تظهر في عام) —</option>' : "") +
      glCats.map((x) => `<option value="${esc(x.key)}">${esc(x.nameAr)}</option>`).join("");
    $("gl_move_to").innerHTML = opts(true);
    $("glCats").querySelector("tbody").innerHTML = glCats
      .map(
        (x) => `<tr>
        <td>${x.imageUrl ? `<img src="${esc(imgUrl(x.imageUrl))}" style="width:36px;height:36px;object-fit:contain;border-radius:8px">` : '<span class="cell-muted">—</span>'}
          <input type="file" accept="image/*" style="display:none" id="gl_img_${esc(x.id)}" onchange="glUploadImage('${esc(x.id)}')">
          <button class="btn btn-outline btn-sm" onclick="document.getElementById('gl_img_${esc(x.id)}').click()">صورة</button></td>
        <td><input class="form-input form-input--sm" id="gl_name_${esc(x.id)}" value="${esc(x.nameAr)}" style="width:140px"></td>
        <td class="cell-muted">${esc(x.key)}</td>
        <td><input type="number" class="form-input form-input--sm" id="gl_order_${esc(x.id)}" value="${Number(x.sortOrder) || 0}" style="width:80px"></td>
        <td><input type="checkbox" id="gl_active_${esc(x.id)}" ${x.isActive ? "checked" : ""}></td>
        <td>${n(x.giftCount)}</td>
        <td><button class="btn btn-primary btn-sm" onclick="glSave('${esc(x.id)}')">حفظ</button>
          ${x.key === "general" ? "" : `<button class="btn btn-outline btn-sm" onclick="glDelete('${esc(x.id)}', ${Number(x.giftCount) || 0})">حذف</button>`}</td>
      </tr>`,
      )
      .join("");
    glRenderGifts();
  }

  function glRenderGifts() {
    const filter = val("gl_filter");
    const label = (k) => glCats.find((x) => x.key === k)?.nameAr || (k ? k : "عام");
    const rows = glGifts.filter((g) => !filter || (filter === "__none" ? !g.category : g.category === filter));
    $("glGifts").querySelector("tbody").innerHTML = rows
      .map(
        (g) => `<tr>
        <td><input type="checkbox" ${glSelected.has(String(g.id)) ? "checked" : ""} onchange="glToggle('${esc(g.id)}', this.checked)"></td>
        <td>${g.iconUrl ? `<img src="${esc(imgUrl(g.iconUrl))}" style="width:32px;height:32px;object-fit:contain">` : ""}</td>
        <td>${esc(g.nameAr || g.name)}</td>
        <td>${esc(label(g.category))}</td>
        <td>${n(g.coinCost)}</td>
      </tr>`,
      )
      .join("");
    $("gl_count").textContent = `${glSelected.size} محددة`;
    $("gl_filter").innerHTML =
      '<option value="">كل الهدايا</option><option value="__none">بدون قائمة</option>' +
      glCats.map((x) => `<option value="${esc(x.key)}" ${filter === x.key ? "selected" : ""}>${esc(x.nameAr)}</option>`).join("");
    if (filter) $("gl_filter").value = filter;
  }

  function glToggle(id, on) {
    if (on) glSelected.add(String(id));
    else glSelected.delete(String(id));
    $("gl_count").textContent = `${glSelected.size} محددة`;
  }

  async function glAdd() {
    const nameAr = val("gl_new_name");
    if (!nameAr) return toast("اكتب اسم القائمة");
    await call("/admin/gifts/categories", "POST", { nameAr, key: val("gl_new_key") || undefined });
    $("gl_new_name").value = "";
    $("gl_new_key").value = "";
    toast("✅ تمت إضافة القائمة");
    giftListsLoad();
  }

  async function glSave(id) {
    await call(`/admin/gifts/categories/${id}`, "PATCH", {
      nameAr: val(`gl_name_${id}`),
      sortOrder: Number(val(`gl_order_${id}`) || 0),
      isActive: $(`gl_active_${id}`).checked,
    });
    toast("✅ تم الحفظ");
    giftListsLoad();
  }

  async function glUploadImage(id) {
    const file = $(`gl_img_${id}`)?.files?.[0];
    if (!file) return;
    const fd = new FormData();
    fd.append("image", file);
    const d = await apiFetch("/upload/image", { method: "POST", body: fd });
    const url = d?.url || d?.imageUrl;
    if (!url) return toast("لم يتم رفع الصورة");
    await call(`/admin/gifts/categories/${id}`, "PATCH", { imageUrl: url });
    toast("✅ تم تغيير صورة القائمة");
    giftListsLoad();
  }

  async function glDelete(id, count) {
    let mode = "general";
    if (count > 0) {
      const ans = prompt(
        `في القائمة ${count} هدية. اكتب 1 لنقل الهدايا إلى «عام» أو 2 لحذف ارتباط الهدايا بالقائمة (الهدايا نفسها لا تُحذف):`,
        "1",
      );
      if (ans == null) return;
      mode = ans.trim() === "2" ? "unlink" : "general";
    } else if (!confirm("حذف القائمة؟")) return;
    await apiFetch(`/admin/gifts/categories/${id}`, { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ mode }) });
    toast("✅ تم حذف القائمة");
    giftListsLoad();
  }

  async function glMove() {
    if (!glSelected.size) return toast("حدد هدايا أولاً");
    await call("/admin/gifts/bulk-move", "POST", { giftIds: [...glSelected], category: val("gl_move_to") });
    glSelected.clear();
    toast("✅ تم نقل الهدايا");
    giftListsLoad();
  }

  Object.assign(window, { giftListsLoad, glAdd, glSave, glDelete, glMove, glToggle, glUploadImage, glRenderGifts });

  // ── section router hook (called from app.js navigate) ───────────────────
  let sessionsPage = 1;
  async function roomSessionsLoad(page = 1) {
    const params = new URLSearchParams({ page: String(page) });
    for (const [id, key] of [['rsUser', 'userId'], ['rsRoom', 'roomId']]) if (val(id)) params.set(key, val(id));
    for (const [id, key] of [['rsFrom', 'from'], ['rsTo', 'to']]) {
      if (val(id)) {
        const date = new Date(val(id));
        if (!Number.isFinite(date.getTime())) return toast('تاريخ غير صالح');
        params.set(key, date.toISOString());
      }
    }
    try {
      const result = await call('/admin-dashboard/room-sessions?' + params);
      sessionsPage = result.page;
      const labels = { connected: 'متصل', disconnected: 'منقطع', listening: 'يستمع', publishing: 'يتحدث', muted: 'مكتوم', reconnecting: 'يعيد الاتصال', failed: 'فشل', leave: 'مغادرة', kick: 'طرد', ban: 'حظر', lease_expired: 'انتهت مهلة المايك', room_closed: 'أُغلقت الغرفة', switch_room: 'انتقل لغرفة أخرى', server_restart: 'إعادة تشغيل السيرفر' };
      $('roomSessionsTable').querySelector('tbody').innerHTML = (result.data || []).map(r =>
        '<tr>' + [r.id, r.userId, r.roomId, dt(r.joinedAt), dt(r.lastHeartbeat), labels[r.wsState] || r.wsState, labels[r.voiceState] || r.voiceState, r.seatNumber ?? '—', r.lastApi, r.disconnectReason, r.reconnectCount, dt(r.leftAt), labels[r.leaveReason] || r.leaveReason].map(v => '<td>' + esc(v) + '</td>').join('') + '</tr>'
      ).join('') || '<tr><td colspan="13" class="cell-muted">لا توجد جلسات</td></tr>';
      $('rsPrev').disabled = sessionsPage <= 1;
      $('rsNext').disabled = !result.hasMore;
      $('rsPage').textContent = String(sessionsPage);
    } catch (_) { $('roomSessionsTable').querySelector('tbody').innerHTML = '<tr><td colspan="13" class="cell-muted">تعذر تحميل الجلسات</td></tr>'; }
  }
  window.roomSessionsLoad = roomSessionsLoad;
  window.roomSessionsPage = delta => roomSessionsLoad(sessionsPage + delta);
  const loaders = { perms: permsLoad, giftlists: giftListsLoad, roomSessions: roomSessionsLoad };
  window.spec52Register = (sec, fn) => {
    loaders[sec] = fn;
  };
  window.spec52Load = (sec) => {
    // Refresh what this admin may see on every page change (covers logging in
    // after the page loaded).
    loadCaps();
    const fn = loaders[sec];
    if (fn) Promise.resolve(fn()).catch((e) => toast("خطأ: " + (e?.message || e)));
  };
  window.spec52Helpers = { $, esc, toast, val, dt, n, call };

  document.addEventListener("DOMContentLoaded", () => setTimeout(loadCaps, 800));
})();
