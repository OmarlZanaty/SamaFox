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

  // ── SPEC52 #41: قوائم المتجر و ID مميز ───────────────────────────────────
  const specialTr = (ar, en) => typeof window.tr === "function" ? window.tr(ar, en) : ar;
  async function slSpecialLoad() {
    const filter = val("special_filter");
    const r = await call("/admin-dashboard/special-ids" + (filter ? "?userId=" + encodeURIComponent(filter) : ""));
    $("special_holdings").innerHTML = (r?.data || []).map((h) => `<tr>
      <td>${esc(h.userId)}</td><td>${esc(h.displayId)}</td><td>${esc(h.originalDisplayId ?? "—")}</td>
      <td>${h.expiresAt ? esc(dt(h.expiresAt)) : specialTr("دائم", "Permanent")}</td>
      <td><button class="btn btn-outline btn-sm" data-perm="store.products" onclick="slSpecialRevoke(${Number(h.userId)})">${specialTr("سحب", "Revoke")}</button></td>
    </tr>`).join("") || `<tr><td colspan="5">${specialTr("لا توجد آيديات مميزة فعالة", "No active special IDs")}</td></tr>`;
    await loadCaps();
  }
  async function slSpecialGrant() {
    await call("/admin-dashboard/special-ids/grant", "POST", {
      userId: Number(val("special_user")), displayId: Number(val("special_display")),
      durationDays: val("special_days") ? Number(val("special_days")) : null,
    });
    await slSpecialLoad();
  }
  async function slSpecialRevoke(userId) {
    await call("/admin-dashboard/special-ids/revoke", "POST", { userId: userId || Number(val("special_user")) });
    await slSpecialLoad();
  }
  Object.assign(window, { slSpecialLoad, slSpecialGrant, slSpecialRevoke });
  async function storeListsLoad() {
    await loadCaps();
    const r = await call("/admin-dashboard/store-lists");
    const cats = r?.data || [];
    $("sl_bulk_cat").innerHTML = cats.map((c) => `<option value="${c.id}">${esc(c.name)}</option>`).join("");
    $("slBody").innerHTML = cats.map((c) => `
      <div class="form-card" style="margin-top:10px">
        <div class="form-row">
          <input class="form-input" id="sl_name_${c.id}" value="${esc(c.name)}" style="max-width:180px">
          <input class="form-input" id="sl_order_${c.id}" type="number" value="${c.sortOrder}" style="max-width:80px" title="الترتيب">
          <input class="form-input" id="sl_img_${c.id}" value="${esc(c.imageUrl || "")}" placeholder="رابط صورة القائمة" style="max-width:220px">
          <label><input type="checkbox" id="sl_active_${c.id}" ${c.isActive ? "checked" : ""}> ظاهرة</label>
          <button class="btn btn-primary btn-sm" onclick="slSaveCat(${c.id})" data-perm="store.products">حفظ</button>
          <button class="btn btn-outline btn-sm" onclick="slDelCat(${c.id})" data-perm="store.products">حذف</button>
        </div>
        <div class="table-wrap"><table><thead><tr><th>المنتج</th><th>ID</th><th>السعر</th><th>المدة</th><th>المخزون</th><th>متاح</th><th></th></tr></thead><tbody>
        ${(c.products || []).map((p) => `<tr>
          <td><input class="form-input form-input--sm" id="sp_name_${p.id}" value="${esc(p.name)}"></td>
          <td>${p.specialDisplayId ?? "—"}</td>
          <td><input class="form-input form-input--sm" type="number" id="sp_price_${p.id}" value="${p.priceCoins}" style="width:110px"></td>
          <td><input class="form-input form-input--sm" type="number" id="sp_days_${p.id}" value="${p.durationDays ?? ""}" placeholder="أبدي" style="width:80px"></td>
          <td><input class="form-input form-input--sm" type="number" id="sp_stock_${p.id}" value="${p.stock ?? ""}" placeholder="∞" style="width:80px"></td>
          <td><input type="checkbox" id="sp_av_${p.id}" ${p.isAvailable ? "checked" : ""}></td>
          <td><button class="btn btn-primary btn-sm" onclick="slSaveProd(${p.id})" data-perm="store.products">حفظ</button>
              <button class="btn btn-outline btn-sm" onclick="slDelProd(${p.id})" data-perm="store.products">حذف</button></td></tr>`).join("") || '<tr><td colspan="7" class="cell-muted">لا توجد منتجات</td></tr>'}
        </tbody></table></div>
        <div class="form-row">
          <input class="form-input" id="np_name_${c.id}" placeholder="اسم منتج جديد" style="max-width:160px">
          <input class="form-input" id="np_id_${c.id}" type="number" placeholder="ID للبيع (اختياري)" style="max-width:150px">
          <input class="form-input" id="np_price_${c.id}" type="number" placeholder="السعر" style="max-width:110px">
          <button class="btn btn-outline btn-sm" onclick="slAddProd(${c.id})" data-perm="store.products">+ منتج</button>
        </div>
      </div>`).join("") || '<p class="cell-muted">لا توجد قوائم بعد</p>';
    if (window.spec52Can("store.products")) {
      $("slBody").insertAdjacentHTML("beforeend", `<div class="form-card" style="margin-top:10px">
        <h3>${specialTr("منح آيدي مميز / سحب", "Grant / revoke special ID")}</h3>
        <div class="form-row">
          <input class="form-input" id="special_user" type="number" min="1" placeholder="${specialTr("رقم حساب المستخدم", "User account ID")}">
          <input class="form-input" id="special_display" type="number" min="1" placeholder="${specialTr("الآيدي المميز", "Special display ID")}">
          <input class="form-input" id="special_days" type="number" min="1" max="36500" placeholder="${specialTr("الأيام (فارغ = دائم)", "Days (blank = permanent)")}">
          <button class="btn btn-primary" data-perm="store.products" onclick="slSpecialGrant()">${specialTr("منح", "Grant")}</button>
          <button class="btn btn-outline" data-perm="store.products" onclick="slSpecialRevoke()">${specialTr("سحب", "Revoke")}</button>
        </div>
        <div class="form-row">
          <input class="form-input" id="special_filter" type="number" min="1" placeholder="${specialTr("تصفية برقم حساب المستخدم", "Filter by user account ID")}">
          <button class="btn btn-outline" onclick="slSpecialLoad()">${specialTr("عرض", "Show")}</button>
        </div>
        <div class="table-wrap"><table><thead><tr>
          <th>${specialTr("المستخدم", "User")}</th><th>${specialTr("الآيدي المميز", "Special ID")}</th>
          <th>${specialTr("الرقم الأصلي", "Original ID")}</th><th>${specialTr("الانتهاء", "Expires")}</th><th></th>
        </tr></thead><tbody id="special_holdings"></tbody></table></div>
      </div>`);
      await slSpecialLoad();
    }
    loadCaps();
  }
  async function slAddCat() {
    if (!val("sl_new")) return toast("اكتب اسم القائمة");
    await call("/admin-dashboard/store-lists", "POST", { name: val("sl_new") });
    $("sl_new").value = "";
    storeListsLoad();
  }
  async function slSaveCat(id) {
    await call(`/admin-dashboard/store-lists/${id}`, "PATCH", { name: val(`sl_name_${id}`), sortOrder: Number(val(`sl_order_${id}`) || 0), imageUrl: val(`sl_img_${id}`), isActive: $(`sl_active_${id}`).checked });
    toast("✅ تم الحفظ");
  }
  async function slDelCat(id) {
    if (!confirm("إخفاء القائمة ومنتجاتها؟ (لا يُحذف أي سجل شراء)")) return;
    await call(`/admin-dashboard/store-lists/${id}`, "DELETE");
    storeListsLoad();
  }
  async function slAddProd(cat) {
    const body = { categoryId: cat, name: val(`np_name_${cat}`), priceCoins: Number(val(`np_price_${cat}`)) };
    if (val(`np_id_${cat}`)) { body.specialDisplayId = Number(val(`np_id_${cat}`)); body.kind = "special_id"; body.stock = 1; if (!body.name) body.name = "ID " + body.specialDisplayId; }
    await call("/admin-dashboard/store-lists/products", "POST", body);
    storeListsLoad();
  }
  async function slSaveProd(id) {
    await call(`/admin-dashboard/store-lists/products/${id}`, "PATCH", {
      name: val(`sp_name_${id}`), priceCoins: Number(val(`sp_price_${id}`)), durationDays: val(`sp_days_${id}`),
      stock: val(`sp_stock_${id}`), isAvailable: $(`sp_av_${id}`).checked,
    });
    toast("✅ تم حفظ المنتج");
  }
  async function slDelProd(id) {
    if (!confirm("حذف المنتج؟")) return;
    await call(`/admin-dashboard/store-lists/products/${id}`, "DELETE");
    storeListsLoad();
  }
  async function slBulk() {
    const r = await call("/admin-dashboard/store-lists/bulk-ids", "POST", { categoryId: Number(val("sl_bulk_cat")), ids: val("sl_bulk_ids"), priceCoins: Number(val("sl_bulk_price")) });
    toast(`✅ أُضيف ${r?.data?.added ?? 0}، تُخطّي ${(r?.data?.skipped || []).length} (مستخدمة أو معروضة)`);
    storeListsLoad();
  }
  Object.assign(window, { storeListsLoad, slAddCat, slSaveCat, slDelCat, slAddProd, slSaveProd, slDelProd, slBulk });

  // ── SPEC52 #28 / #29: الصاروخ و PK ────────────────────────────────────────
  let evProducts = [];
  let evGifts = [];
  const key = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random());
  async function callKey(path, method, body) {
    try {
      return await apiFetch(path, {
        method,
        headers: { "Content-Type": "application/json", "Idempotency-Key": key() },
        body: JSON.stringify(body),
      });
    } catch (e) {
      toast("❌ " + (e?.message || "فشل"));
      throw e;
    }
  }
  function rewardRow(r = {}) {
    const opts = evProducts.map((p) => `<option value="${esc(p.id)}" ${p.id === r.itemId ? "selected" : ""}>${esc(p.name)}${p.durationDays ? ` (${p.durationDays} يوم)` : ""}</option>`).join("");
    return `<div class="form-row ev-reward" style="gap:6px">
      <select class="form-input ev-type" style="max-width:110px"><option value="coins" ${r.type !== "item" ? "selected" : ""}>كوينز</option><option value="item" ${r.type === "item" ? "selected" : ""}>منتج</option></select>
      <input class="form-input ev-coins" type="number" min="1" placeholder="عدد الكوينز" value="${r.coins ?? ""}" style="max-width:120px">
      <select class="form-input ev-item" style="max-width:220px"><option value="">— المنتج —</option>${opts}</select>
      <input class="form-input ev-weight" type="number" min="1" placeholder="الوزن (الاحتمال)" value="${r.weight ?? 1}" style="max-width:110px">
      <input class="form-input ev-qty" type="number" min="1" placeholder="الكمية" value="${r.quantity ?? 1}" style="max-width:80px">
      <button class="btn btn-outline btn-sm" onclick="this.parentElement.remove()">حذف</button></div>`;
  }
  function readRewards(container) {
    return [...container.querySelectorAll(".ev-reward")].map((row) => {
      const type = row.querySelector(".ev-type").value;
      const r = { type, weight: Number(row.querySelector(".ev-weight").value || 1), quantity: Number(row.querySelector(".ev-qty").value || 1) };
      if (type === "coins") r.coins = Number(row.querySelector(".ev-coins").value || 0);
      else r.itemId = row.querySelector(".ev-item").value;
      return r;
    });
  }
  // PK levels (client 10/11 19:48): threshold + prizes for each level.
  function pkLevelRow(l = {}) {
    const coinsIn = (list) => (list || []).filter((r) => r.type === "coins" || r.type === "both").reduce((n, r) => n + Number(r.coins || 0) * Number(r.quantity || 1), 0);
    const itemsIn = (list) => (list || []).filter((r) => r.type === "item" || r.type === "both").map((r) => r.itemId);
    const opts = (sel) => evProducts.map((p) => `<option value="${esc(p.id)}" ${sel.includes(p.id) ? "selected" : ""}>${esc(p.name)}${p.durationDays ? ` (${p.durationDays} يوم)` : ""}</option>`).join("");
    return `<div class="form-row pk-level" style="gap:6px;align-items:flex-end;border-top:1px dashed #555;padding-top:6px">
      <label>يفتح عند مجموع <input class="form-input pl-min" type="number" min="0" value="${esc(String(l.minTotalCoins ?? ""))}" style="max-width:130px"></label>
      <label>كوينز الفايز <input class="form-input pl-wc" type="number" min="0" value="${coinsIn(l.winner) || ""}" style="max-width:110px"></label>
      <label>منتجات الفايز (اختار أكتر من واحد بـ Ctrl) <select class="form-input pl-wi" multiple style="height:72px;max-width:220px">${opts(itemsIn(l.winner))}</select></label>
      <label>كوينز الخسران <input class="form-input pl-lc" type="number" min="0" value="${coinsIn(l.loser) || ""}" style="max-width:110px"></label>
      <label>كوينز لكل مشاهد <input class="form-input pl-vc" type="number" min="0" value="${coinsIn(l.viewer) || ""}" style="max-width:110px"></label>
      <label>منتج لكل مشاهد <select class="form-input pl-vi" style="max-width:200px"><option value="">بدون</option>${opts(itemsIn(l.viewer))}</select></label>
      <button class="btn btn-outline btn-sm" onclick="this.closest('.pk-level').remove()">حذف</button></div>`;
  }
  function readPkLevels() {
    const list = (coins, items) => [
      ...(coins > 0 ? [{ type: "coins", coins, quantity: 1, weight: 1 }] : []),
      ...items.filter(Boolean).map((itemId) => ({ type: "item", itemId, quantity: 1, weight: 1 })),
    ];
    return [...document.querySelectorAll("#pk_levels .pk-level")].map((row) => ({
      minTotalCoins: Number(row.querySelector(".pl-min").value || 0),
      winner: list(Number(row.querySelector(".pl-wc").value || 0), [...row.querySelector(".pl-wi").selectedOptions].map((o) => o.value)),
      loser: list(Number(row.querySelector(".pl-lc").value || 0), []),
      viewer: list(Number(row.querySelector(".pl-vc").value || 0), [row.querySelector(".pl-vi").value]),
    }));
  }
  // Rocket tiers (client 10/11 19:48): target + prizes for top 1/2/3.
  function rkTierRow(t = {}) {
    const top = t.topRewards || [];
    const coinsIn = (list) => (list || []).filter((r) => r.type === "coins" || r.type === "both").reduce((n, r) => n + Number(r.coins || 0) * Number(r.quantity || 1), 0);
    const itemIn = (list) => ((list || []).find((r) => r.type === "item" || r.type === "both") || {}).itemId || "";
    const opts = (sel) => `<option value="">بدون منتج</option>` + evProducts.map((p) => `<option value="${esc(p.id)}" ${p.id === sel ? "selected" : ""}>${esc(p.name)}</option>`).join("");
    const rank = (i) => `<label>الأول${["", " (2)", " (3)"][i]} — ${["🥇", "🥈", "🥉"][i]} كوينز <input class="form-input rt-c${i}" type="number" min="0" value="${coinsIn(top[i]) || ""}" style="max-width:110px"></label>
      <label>منتج <select class="form-input rt-i${i}" style="max-width:180px">${opts(itemIn(top[i]))}</select></label>`;
    return `<div class="form-row rk-tier" style="gap:6px;align-items:flex-end;border-top:1px dashed #555;padding-top:6px">
      <label>الهدف (كوينز) <input class="form-input rt-target" type="number" min="1" value="${esc(String(t.targetCoins ?? ""))}" style="max-width:140px"></label>
      ${rank(0)}${rank(1)}${rank(2)}
      <button class="btn btn-outline btn-sm" onclick="this.closest('.rk-tier').remove()">حذف</button></div>`;
  }
  function readRkTiers() {
    return [...document.querySelectorAll("#rk_tiers .rk-tier")].map((row) => ({
      targetCoins: Number(row.querySelector(".rt-target").value || 0),
      topRewards: [0, 1, 2].map((i) => {
        const c = Number(row.querySelector(`.rt-c${i}`).value || 0);
        const item = row.querySelector(`.rt-i${i}`).value;
        return [...(c > 0 ? [{ type: "coins", coins: c, quantity: 1, weight: 1 }] : []), ...(item ? [{ type: "item", itemId: item, quantity: 1, weight: 1 }] : [])];
      }),
    }));
  }
  async function rocketPkLoad() {
    await loadCaps();
    const [rk, pk] = await Promise.all([call("/admin-dashboard/rocket"), call("/admin-dashboard/pk")]);
    const R = rk?.data || {};
    const P = pk?.data || {};
    evProducts = R.products || [];
    evGifts = P.gifts || [];
    const c = R.config || {};
    $("rk_target").value = c.targetCoins ?? 1000000;
    $("rk_pct").value = c.roomCupPercent != null ? c.roomCupPercent / 100 : 10;
    $("rk_minutes").value = c.durationMinutes ?? 30;
    $("rk_winners").value = c.winnersCount ?? 10;
    $("rk_max").value = c.maxRewardPerUserCoins ?? 1000;
    $("rk_window").value = c.claimWindowSeconds ?? 90;
    $("rk_active").checked = !!c.isActive;
    $("rk_rewards").innerHTML = (c.rewards || [{ type: "coins", coins: 100, weight: 1, quantity: 1 }]).map(rewardRow).join("");
    $("rk_tiers").innerHTML = (c.tiers || []).map(rkTierRow).join("");
    $("rk_pool").textContent = n(R.poolBalance);
    const rkSt = $("rk_status");
    if (!R.config || !R.config.isActive) { rkSt.style.color = "#e53935"; rkSt.textContent = "⚠️ الصاروخ غير مفعّل — فعّل خانة «مفعّل» واحفظ حتى يظهر تقدمه ويبدأ العد"; }
    else if (!Number(R.poolBalance)) { rkSt.style.color = "#fb8c00"; rkSt.textContent = "⚠️ صندوق الجوائز فارغ — موّله حتى يقدر المستخدمون يستلموا"; }
    else { rkSt.style.color = "#43a047"; rkSt.textContent = "✅ الصاروخ مفعّل والصندوق ممول"; }
    $("rkEvents").querySelector("tbody").innerHTML = (R.events || []).map((e) => `<tr><td>${esc(e.roomId)}</td><td>${esc(e.status)}</td><td>${n(e.currentCoins)} / ${n(e.targetCoins)}</td><td>${dt(e.startedAt)}</td><td>${dt(e.launchedAt)}</td><td>${(e.claims || []).length}</td></tr>`).join("") || '<tr><td colspan="6" class="cell-muted">لا توجد أحداث</td></tr>';
    const q = P.config || {};
    $("pk_durations").value = (q.allowedDurations || [180, 300, 600]).join(",");
    $("pk_ppc").value = q.pointsPerCoin ?? 1;
    $("pk_tie").value = q.tieRule || "TIE";
    $("pk_enabled").checked = !!q.enabled;
    $("pk_gifts").innerHTML = evGifts.map((g) => `<option value="${esc(g.id)}" ${(q.countedGiftIds || []).includes(g.id) ? "selected" : ""}>${esc(g.nameAr || g.name)}</option>`).join("");
    const pkTr = (ar, en) => typeof window.tr === 'function' ? window.tr(ar, en) : ar;
    const pkOptions = (selected) => `<option value="">${pkTr('بدون منتج', 'No product')}</option>` + evProducts.map(p => `<option value="${esc(p.id)}" ${p.id === selected ? 'selected' : ''}>${esc(p.name)}</option>`).join('');
    const winner = q.rewards?.winner || {};
    $("pk_win").innerHTML = `<div class="form-row">
      <label>${pkTr('كوينز الفائز', 'Winner coins')} <input id="pk_win_coins" class="form-input" type="number" min="0" max="1000000" value="${Number(winner.coins || 0)}"></label>
      <label>${pkTr('منتج الفائز', 'Winner product')} <select id="pk_win_item" class="form-input">${pkOptions(winner.itemId)}</select></label>
      <label>${pkTr('الكمية', 'Quantity')} <input id="pk_win_qty" class="form-input" type="number" min="1" max="100" value="${Number(winner.quantity || 1)}"></label></div>`;
    $("pk_prize_settings").innerHTML = `<div class="form-row">
      <label>${pkTr('الحد الأدنى لمجموع PK للجوائز', 'Minimum PK total for prizes')} <input id="pk_min_total" class="form-input" type="number" min="0" value="${esc(String(q.minTotalCoins ?? 0))}"></label>
      <label>${pkTr('كوينز لكل مشاهد', 'Coins per viewer')} <input id="pk_viewer_coins" class="form-input" type="number" min="0" max="1000000" value="${Number(q.viewerGiftCoins || 0)}"></label>
      <label>${pkTr('منتج لكل مشاهد', 'Product per viewer')} <select id="pk_viewer_item" class="form-input">${pkOptions(q.viewerGiftItem?.itemId)}</select></label></div>`;
    $("pk_levels").innerHTML = (q.levels || []).map(pkLevelRow).join("");
    $("pk_pool").textContent = n(P.poolBalance);
    $("pkEvents").querySelector("tbody").innerHTML = (P.events || []).map((e) => `<tr><td>${esc(e.type)}</td><td>${esc(e.room1Id)} / ${esc(e.room2Id)}</td><td>${esc(e.status)}</td><td>${n(e.room1Score)} : ${n(e.room2Score)}</td><td>${esc(e.winner || "—")}</td><td>${dt(e.createdAt)}</td></tr>`).join("") || '<tr><td colspan="6" class="cell-muted">لا توجد مباريات</td></tr>';
  }
  async function rocketSave() {
    await callKey("/admin-dashboard/rocket/config", "PUT", {
      targetCoins: Number(val("rk_target")),
      roomCupPercent: Math.round(Number(val("rk_pct")) * 100),
      durationMinutes: Number(val("rk_minutes")),
      winnersCount: Number(val("rk_winners")),
      maxRewardPerUserCoins: Number(val("rk_max")),
      claimWindowSeconds: Number(val("rk_window")),
      isActive: $("rk_active").checked,
      rewards: readRewards($("rk_rewards")),
      tiers: readRkTiers(),
    });
    toast("✅ تم حفظ إعدادات الصاروخ");
    rocketPkLoad();
  }
  async function pkSave() {
    const coins = Number(val("pk_win_coins") || 0);
    const itemId = val("pk_win_item");
    const winner = { type: itemId ? (coins > 0 ? 'both' : 'item') : 'coins',
      ...(coins > 0 || !itemId ? { coins } : {}), ...(itemId ? { itemId } : {}),
      quantity: Number(val("pk_win_qty") || 1), weight: 1 };
    await callKey("/admin-dashboard/pk/config", "PUT", {
      allowedDurations: val("pk_durations").split(",").map((x) => Number(x.trim())).filter(Boolean),
      countedGiftIds: [...$("pk_gifts").selectedOptions].map((o) => o.value),
      pointsPerCoin: Number(val("pk_ppc") || 1),
      winCondition: "HIGHER_SCORE",
      tieRule: val("pk_tie"),
      enabled: $("pk_enabled").checked,
      minTotalCoins: val("pk_min_total") || '0',
      viewerGiftCoins: Number(val("pk_viewer_coins") || 0),
      viewerGiftItem: val("pk_viewer_item") || null,
      rewards: coins > 0 || itemId ? { winner } : {},
      levels: readPkLevels(),
    });
    toast("✅ تم حفظ إعدادات PK");
    rocketPkLoad();
  }
  async function eventFund(kind) {
    const amount = Number(prompt(kind === "rocket" ? "مبلغ تمويل صندوق الصاروخ (كوينز):" : "مبلغ تمويل صندوق PK (كوينز):", "100000"));
    if (!amount) return;
    await callKey(`/admin-dashboard/${kind}/fund`, "POST", { amount });
    toast("✅ تم التمويل");
    rocketPkLoad();
  }
  Object.assign(window, { rkAddTier: () => $("rk_tiers").insertAdjacentHTML("beforeend", rkTierRow()), pkAddLevel: () => $("pk_levels").insertAdjacentHTML("beforeend", pkLevelRow()), rocketPkLoad, rocketSave, pkSave, eventFund, evAddReward: () => $("rk_rewards").insertAdjacentHTML("beforeend", rewardRow()) });

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
  const loaders = { perms: permsLoad, giftlists: giftListsLoad, roomSessions: roomSessionsLoad, rocketpk: rocketPkLoad, storelists: storeListsLoad };
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
