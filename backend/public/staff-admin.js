/* Staff dashboard. Uses the authenticated API and escaping helpers from app.js. */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const esc = (value) => escapeHtml(String(value ?? ""));
  const base = "/admin-dashboard/staff";
  const roles = { MANAGER: "👑 Manager", SUPER_ADMIN: "💎 Super Admin", ADMIN: "🛡️ Admin" };
  const permissions = {
    role_panel: "نظام الدور (Super Admin / Admin)", manage_admins: "تعيين Admin", grant_vip: "منح VIP",
    grant_level: "منح Level", grant_frame: "منح إطار", grant_entry: "منح دخولية",
    grant_bubble: "منح فقاعة دردشة", manage_host_agency: "تعيين وكالة مضيفين",
    follow_agencies: "متابعة الوكالات", ban_users: "نظام الحظر",
  };
  const types = { FRAME: "إطار", ENTRANCE_BANNER: "شريط دخول", ENTRANCE_EFFECT: "تأثير دخول",
    CHAT_BUBBLE: "فقاعة دردشة", BADGE: "شارة", PROFILE_BACKGROUND: "خلفية الملف",
    PROFILE_DECOR: "زينة الملف", ROOM_BACKGROUND: "خلفية الغرفة", MIC_FRAME: "إطار الميكروفون" };
  const actions = {
    STAFF_APPOINT: "تعيين إداري", STAFF_EXTEND: "تمديد الإدارة", STAFF_RENEW: "تجديد الإدارة",
    STAFF_REVOKE: "سحب الإدارة", STAFF_EXPIRED: "انتهاء الإدارة", STAFF_PERMISSION_GRANT: "منح صلاحية",
    STAFF_PERMISSION_REVOKE: "سحب صلاحية", STAFF_PERMISSION_EXPIRED: "انتهاء صلاحية",
    STAFF_ALLOWED_ITEMS_SET: "تعديل المنتجات المسموح بها", STAFF_REWARD_ITEMS_SET: "تعديل مكافآت الإداري",
    STAFF_ROLE_REWARDS_CONFIG: "تعديل مكافآت الأدوار", STAFF_GRANTABLE_POOL_SET: "تعديل قائمة منتجات المنح",
    STAFF_REPARENT: "تغيير المسؤول الأعلى", STAFF_GRANT_VIP: "منح VIP", STAFF_GRANT_LEVEL: "منح Level",
    STAFF_GRANT_ITEM: "منح منتج", STAFF_GRANT_REVOKE: "سحب منحة", STAFF_GRANT_EXPIRED: "انتهاء منحة",
    STAFF_AGENCY_CREATE: "إنشاء وكالة مضيفين", STAFF_AGENCY_FOLLOWER_ADD: "إضافة متابع لوكالة",
    STAFF_AGENCY_FOLLOWER_REMOVE: "إزالة متابع وكالة", STAFF_BAN: "حظر مستخدم",
    STAFF_UNBAN: "رفع الحظر", STAFF_BAN_EXPIRED: "انتهاء الحظر",
  };
  const state = { canWrite: false, members: [], items: [], pool: [], rewards: {}, page: 1, fileId: null };
  const versions = {};
  const busy = new Set();
  const value = (id) => $(id).value.trim();
  const date = (v) => v ? esc(new Date(v).toLocaleString("ar-EG")) : "—";
  const endDate = (v) => v ? date(v) : "دائم";
  const effectiveStatus = (r) => r.status === "ACTIVE" && r.expiresAt && new Date(r.expiresAt) <= new Date() ? "EXPIRED" : r.status;
  function status(r) {
    const s = effectiveStatus(r);
    return `<span class="badge ${s === "ACTIVE" ? "badge-approved" : "badge-rejected"}">${({ ACTIVE: "🟢 نشط", EXPIRED: "🔴 منتهي", REVOKED: "ملغى", LIFTED: "رُفع الحظر" })[s] || "غير محدد"}</span>`;
  }
  function person(user, id) {
    if (id === 0) return "النظام";
    return user ? `${esc(user.name || "—")}<div class="cell-muted">المعرّف الظاهر: ${esc(user.displayId ?? "—")} · الداخلي: ${esc(user.id)}</div>` : id ? `المعرّف الداخلي: ${esc(id)}` : "—";
  }
  const actor = (id) => person(state.members.find(r => r.userId === id)?.user, id);
  const options = (entries, all) => `<option value="">${all}</option>` + Object.entries(entries).map(([k, v]) => `<option value="${esc(k)}">${esc(v)}</option>`).join("");
  const table = (headers, rows) => `<div class="table-wrap"><table><thead><tr>${headers.map(h => `<th>${h}</th>`).join("")}</tr></thead><tbody>${rows.join("") || `<tr><td colspan="${headers.length}" class="cell-muted">لا توجد سجلات</td></tr>`}</tbody></table></div>`;
  const button = (action, label, id = "") => `<button type="button" class="btn btn-outline btn-sm" data-staff-action="${action}" data-id="${esc(id)}">${label}</button>`;
  const card = (title, content) => `<div class="form-card" style="margin-top:18px"><h3 class="form-card-title">${title}</h3>${content}</div>`;
  const json = (v) => v == null ? "—" : `<details><summary>عرض البيانات</summary><pre dir="auto" style="white-space:pre-wrap;overflow-wrap:anywhere;max-width:440px">${esc(JSON.stringify(v, null, 2))}</pre></details>`;
  async function api(path, method = "GET", body) {
    const result = await apiFetch(base + path, method, body);
    if (!result || result.success === false) throw new Error(result?.message || "تعذر تحميل البيانات");
    return result.data;
  }
  function errorText(error) {
    return /[\u0600-\u06ff]/.test(error?.message || "") ? error.message : "تعذر تنفيذ الطلب، تحقق من الاتصال وصلاحية تسجيل الدخول";
  }
  // Each panel fails independently; an incomplete settings load can never be saved.
  async function loadPanel(id, work) {
    const version = versions[id] = (versions[id] || 0) + 1;
    $(id).innerHTML = '<p role="status">جارٍ التحميل…</p>';
    try {
      const render = await work();
      if (versions[id] === version) render();
    } catch (error) {
      if (versions[id] === version) $(id).innerHTML = `<p role="alert">${esc(errorText(error))}</p>${button("retry", "إعادة المحاولة", id)}`;
    }
  }
  function init() {
    $("staffPanel").innerHTML = card("تعيين Manager", `<form id="staffAppoint" class="form-row">
      <label>نوع المعرّف <select id="staffIdKind" class="form-select"><option value="displayId">المعرّف الظاهر</option><option value="userId">المعرّف الداخلي</option></select></label>
      <label>معرّف المستخدم <input id="staffUserId" class="form-input" type="number" min="1" step="1" required></label>
      <label>المدة بالأيام <input id="staffDays" class="form-input form-input--sm" type="number" min="1" max="365" step="1" value="30" required></label>
      <button class="btn btn-primary" type="submit" disabled>تعيين Manager</button></form>`)
      + card("الإداريون", `<form id="staffFilters" class="form-row"><label>الدور <select id="staffRoleFilter" class="form-select">${options(roles, "كل الأدوار")}</select></label>
      <label>الحالة <select id="staffStatusFilter" class="form-select">${options({ ACTIVE: "نشط", EXPIRED: "منتهي", REVOKED: "ملغى" }, "كل الحالات")}</select></label><button class="btn btn-outline">تطبيق</button></form><div id="staffMembers"></div>`)
      + '<div id="staffActionBox" hidden></div><div id="staffFile" hidden tabindex="-1"></div>'
      + card("قائمة المنتجات المسموح بها", '<p class="settings-hint">منتجات المنح المؤقتة: الإطارات والدخوليات وفقاعات الدردشة.</p><div id="staffPool"></div>')
      + card("مكافآت الإدارة", '<p class="settings-hint">اختر إطار الإدارة وشارتها وأي منتجات إضافية لكل دور.</p><div id="staffRewards"></div>')
      + card("حاملو صلاحية الحظر", '<p class="settings-hint">للعرض فقط. تشمل القائمة المديرين الذين يملكون الصلاحية تلقائيًا.</p><div id="staffHolders"></div>')
      + card("المنح المؤقتة", '<div id="staffGrants"></div>')
      + card("حظر نظام الإدارة", '<div id="staffBans"></div>')
      + card("سجل عمليات الإدارة", `<form id="staffAuditFilters" class="form-row"><label>المعرّف الداخلي للفاعل <input id="staffAuditActor" class="form-input" type="number" min="0" step="1" placeholder="الكل؛ ٠ لعمليات النظام"></label>
      <label>العملية <select id="staffAuditAction" class="form-select">${options(actions, "كل العمليات")}</select></label><button class="btn btn-outline">بحث</button></form><div id="staffAudit"></div>`);
  }
  function renderMembers() {
    const rows = state.members.filter(r => (!value("staffRoleFilter") || r.role === value("staffRoleFilter")) && (!value("staffStatusFilter") || effectiveStatus(r) === value("staffStatusFilter")));
    $("staffMembers").innerHTML = table(["المعرّف", "الاسم", "الدور", "يتبع", "البداية", "النهاية", "الحالة", "عيّنه", "الإجراءات"], rows.map(r => {
      const active = effectiveStatus(r) === "ACTIVE";
      return `<tr><td>${esc(r.user?.displayId ?? r.userId)}<div class="cell-muted">الداخلي: ${esc(r.userId)} · التعيين: ${esc(r.id)}</div></td><td>${esc(r.user?.name || "—")}</td><td>${esc(roles[r.role] || "—")}</td>
        <td>${r.parentUserId == null ? (r.role === "MANAGER" ? "إدارة المنصة" : "بلا Manager — يحتاج تغيير المدير") : person(r.parent, r.parentUserId)}</td><td>${date(r.startedAt)}</td><td>${date(r.expiresAt)}</td><td>${status(r)}</td><td>${person(r.assignedBy, r.assignedById)}</td>
        <td><div class="td-actions">${button("file", "عرض الملف", r.id)}${state.canWrite ? button(active ? "extend" : "renew", active ? "تمديد" : "تجديد", r.id) + (active ? button("revoke", "سحب", r.id) : "") + (active && r.role !== "MANAGER" && r.parentUserId == null ? button("parent", "تغيير المدير", r.id) : "") : ""}</div></td></tr>`;
    }));
  }
  function loadMembers() {
    return loadPanel("staffMembers", async () => {
      const rows = await api("");
      return () => { state.members = rows; renderMembers(); };
    });
  }
  function thumbnail(item) {
    const raw = item.preview_url || item.previewUrl || item.file_url || item.assetUrl;
    let url;
    try { url = new URL(raw, document.baseURI); } catch { return "🖼️"; }
    if (!raw || !["http:", "https:"].includes(url.protocol) || /\.(mp4|webm|svga)(?:$|\?)/i.test(url.href)) return '<span aria-label="لا توجد معاينة">🖼️</span>';
    return `<img src="${esc(url.href)}" alt="${esc(item.name || "معاينة المنتج")}" loading="lazy" width="48" height="48" style="object-fit:contain" data-staff-thumbnail>`;
  }
  function picker(id, selected, grantOnly) {
    const allowed = ["FRAME", "ENTRANCE_BANNER", "ENTRANCE_EFFECT", "CHAT_BUBBLE"];
    const items = state.items.filter(i => !grantOnly || allowed.includes(i.type));
    // Retain configured IDs missing from the catalog instead of silently deleting them on save.
    for (const itemId of selected) if (!items.some(i => i.id === itemId)) items.push({ id: itemId, name: "منتج غير متاح في القائمة" });
    return `<label>بحث عن منتج <input class="form-input" type="search" data-staff-search="${id}" placeholder="اسم المنتج أو معرّفه"></label><div id="${id}" style="max-height:300px;overflow:auto;margin:12px 0">${items.map(i => `<label data-item-search="${esc(`${i.name} ${i.id}`.toLocaleLowerCase())}" style="display:flex;align-items:center;gap:10px;padding:8px;border-bottom:1px solid var(--card-border)">
      <input type="checkbox" value="${esc(i.id)}" ${selected.includes(i.id) ? "checked" : ""} ${state.canWrite ? "" : "disabled"}>${thumbnail(i)}<span>${esc(i.name)}<span class="cell-muted"> · ${esc(types[i.type] || "منتج إضافي")} · ${esc(i.id)}</span></span></label>`).join("") || '<p class="cell-muted">لا توجد منتجات</p>'}</div>`;
  }
  async function catalog() {
    const result = await apiFetch("/admin-products/products");
    if (!Array.isArray(result?.data)) throw new Error("تعذر تحميل قائمة المنتجات");
    return result.data;
  }
  function loadPool() {
    return loadPanel("staffPool", async () => {
      const [items, pool] = await Promise.all([catalog(), api("/pool")]);
      return () => {
        state.items = items; state.pool = pool.map(i => i.id);
        $("staffPool").innerHTML = `<form id="staffPoolForm">${picker("staffPoolPicker", state.pool, true)}${state.canWrite ? '<button class="btn btn-primary">حفظ قائمة المنح</button>' : ""}</form>`;
      };
    });
  }
  function loadRewards() {
    return loadPanel("staffRewards", async () => {
      const [items, rewards] = await Promise.all([catalog(), api("/role-rewards")]);
      return () => {
        state.items = items; state.rewards = rewards;
        $("staffRewards").innerHTML = Object.entries(roles).map(([role, label]) => `<details><summary>${label}</summary><form data-staff-rewards="${role}">${picker(`staffReward_${role}`, rewards[role] || [], false)}${state.canWrite ? '<button class="btn btn-primary">حفظ مكافآت هذا الدور</button>' : ""}</form></details>`).join("");
      };
    });
  }
  function loadHolders() {
    return loadPanel("staffHolders", async () => {
      const [holders, managers] = await Promise.all([api("/ban-holders"), api("?role=MANAGER&status=ACTIVE")]);
      return () => {
        const automatic = managers.map(r => ({ ...r, grantedAt: r.startedAt, grantedById: r.assignedById, automatic: true }));
        const rows = [...automatic, ...holders.filter(p => !managers.some(r => r.userId === p.userId))];
        $("staffHolders").innerHTML = table(["المستخدم", "مصدر الصلاحية", "منحها", "البداية", "النهاية", "الحالة"], rows.map(p => `<tr><td>${person(p.user, p.userId)}</td><td>${p.automatic ? "تلقائية للـ Manager" : p.staffRoleId ? "مرتبطة بالتعيين " + esc(p.staffRoleId) : "مستقلة"}</td><td>${actor(p.grantedById)}</td><td>${date(p.grantedAt)}</td><td>${endDate(p.expiresAt)}</td><td>${status(p)}</td></tr>`));
      };
    });
  }
  function loadGrants() {
    return loadPanel("staffGrants", async () => {
      const rows = await api("/grants");
      return () => { $("staffGrants").innerHTML = table(["المنحة", "منحها", "المستفيد", "النوع", "القيمة / المنتج", "المصدر", "البداية", "النهاية", "الحالة"], rows.map(r => `<tr><td>${esc(r.id)}</td><td>${person(r.grantedBy, r.grantedById)}</td><td>${person(r.user, r.userId)}</td><td>${({ VIP: "VIP", LEVEL: "Level", ITEM: "منتج" })[r.type] || "—"}</td><td>${esc(r.type === "ITEM" ? (r.item?.name || state.items.find(i => i.id === r.itemId)?.name || r.itemId) : r.value)}</td><td>${r.source === "ROLE_REWARD" ? "مكافأة إدارة" : "منحة مؤقتة"}</td><td>${date(r.startedAt)}</td><td>${endDate(r.expiresAt)}</td><td>${status(r)}</td></tr>`)); };
    });
  }
  function loadBans() {
    return loadPanel("staffBans", async () => {
      const rows = await api("/bans");
      return () => { $("staffBans").innerHTML = table(["السجل", "المحظور", "حظره", "المدة", "السبب", "البداية", "النهاية", "الحالة", "رفع الحظر"], rows.map(r => `<tr><td>${esc(r.id)}</td><td>${person(r.user, r.userId)}</td><td>${person(r.bannedBy, r.bannedById)}</td><td>${({ "1d": "يوم", "7d": "أسبوع", "30d": "شهر", "365d": "سنة", permanent: "أبدي" })[r.duration] || "—"}</td><td>${esc(r.reason)}</td><td>${date(r.startedAt)}</td><td>${endDate(r.expiresAt)}</td><td>${status(r)}</td><td>${r.liftedAt ? (r.liftedById ? person(r.liftedBy, r.liftedById) : "تلقائي") + "<br>" + date(r.liftedAt) : "—"}</td></tr>`)); };
    });
  }
  function auditTable(rows) {
    const targets = { user: "مستخدم", staff: "تعيين", agency: "وكالة", grant: "منحة", ban: "حظر", setting: "إعداد" };
    return table(["العملية", "التاريخ", "الفاعل", "الإجراء", "الهدف", "قبل", "بعد", "السبب", "عنوان الاتصال والجهاز"], rows.map(r => `<tr><td>${esc(r.id)}</td><td>${date(r.createdAt)}</td><td>${person(r.actor, r.adminId)}</td><td>${esc(actions[r.action] || "عملية إدارية أخرى")}</td><td>${esc(targets[r.targetType] || "—")} · ${esc(r.targetId)}${r.targetUserId ? "<br>" + person(r.targetUser, r.targetUserId) : ""}</td><td>${json(r.before)}</td><td>${json(r.after)}</td><td>${esc(r.reason || "—")}</td><td dir="auto">${esc(r.ip || "—")}<div class="cell-muted">${esc(r.userAgent || "—")}</div></td></tr>`));
  }
  function loadAudit(page = 1) {
    const query = new URLSearchParams({ page: String(page) });
    if (value("staffAuditActor")) query.set("actorId", value("staffAuditActor"));
    if (value("staffAuditAction")) query.set("action", value("staffAuditAction"));
    return loadPanel("staffAudit", async () => {
      const data = await api("/audit?" + query);
      return () => {
        state.page = data.page;
        const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
        $("staffAudit").innerHTML = auditTable(data.rows) + `<div class="form-row" style="margin-top:12px" aria-live="polite">${esc(data.total)} عملية · الصفحة ${esc(data.page)} من ${pages} ${data.page > 1 ? button("page", "السابق", data.page - 1) : ""}${data.page < pages ? button("page", "التالي", data.page + 1) : ""}</div>`;
      };
    });
  }
  function itemList(ids) {
    return ids.length ? `<ul>${ids.map(id => `<li>${esc(state.items.find(i => i.id === id)?.name || "منتج")} · ${esc(id)}</li>`).join("")}</ul>` : '<p class="cell-muted">لا توجد منتجات</p>';
  }
  function openFile(id) {
    state.fileId = id;
    $("staffFile").hidden = false;
    $("staffFile").focus();
    return loadPanel("staffFile", async () => {
      const [file, rewards, pool] = await Promise.all([api("/" + id), api("/role-rewards"), api("/pool")]);
      return () => {
        const r = file.role;
        const active = effectiveStatus(r) === "ACTIVE";
        const latest = new Map();
        for (const p of file.permissions) if (!latest.has(p.permission)) latest.set(p.permission, p);
        const checks = Object.entries(permissions).map(([key, label]) => {
          const p = latest.get(key);
          const on = active && (r.role === "MANAGER" || (p && effectiveStatus(p) === "ACTIVE"));
          return `<tr><td>${label}</td><td>${on ? "متاحة" : "غير متاحة"}</td><td>${p ? endDate(p.expiresAt) : r.role === "MANAGER" ? "حتى نهاية الإدارة" : "—"}</td></tr>`;
        });
        $("staffFile").innerHTML = card("ملف الإداري", `${button("closeFile", "إغلاق الملف")}<p>${person(file.user, r.userId)} · ${esc(roles[r.role])} · ${status(r)}</p><p>البداية: ${date(r.startedAt)} · النهاية: ${date(r.expiresAt)}</p>
          <h4>الصلاحيات</h4>${table(["الصلاحية", "الإتاحة الحالية", "النهاية"], checks)}
          <h4>المنتجات المسموح بها</h4>${itemList(r.role === "MANAGER" ? pool.map(i => i.id) : file.allowedItemIds)}
          <h4>مكافآت الدور</h4>${itemList(rewards[r.role] || [])}<h4>مكافآت إضافية للإداري</h4>${itemList(file.rewardItemIds)}
          <h4>وكالات المضيفين ضمن نطاقه</h4>${table(["المعرّف", "الوكالة", "المالك", "عدد الأعضاء", "الإنتاج", "المنشئ", "المتابعون"], file.agencies.map(a => `<tr><td>${esc(a.id)}</td><td>${esc(a.agencyName)}</td><td>${person(a.owner, a.owner?.id)}</td><td>${esc(a.membersCount)}</td><td>${esc(a.production)}</td><td>${person(a.creator, a.creator?.id)}</td><td>${a.followers.map(u => person(u, u.id)).join("<br>") || "—"}</td></tr>`))}
          <h4>آخر ٥٠ عملية نفذها</h4>${auditTable(file.audit)}`);
      };
    });
  }
  function openAction(action, id) {
    if (!state.canWrite) return;
    const r = state.members.find(row => row.id === id);
    if (!r) return;
    const label = { extend: "تمديد الإدارة", renew: "تجديد الإدارة", revoke: "سحب الإدارة", parent: "تغيير المدير" }[action];
    let fields;
    if (action === "parent") {
      const managers = state.members.filter(m => m.role === "MANAGER" && effectiveStatus(m) === "ACTIVE" && m.userId !== r.userId);
      fields = `<label>المدير الجديد <select name="parentUserId" class="form-select" required><option value="">اختر المدير</option>${managers.map(m => `<option value="${m.userId}">${esc(m.user?.name || "مدير")} · ${esc(m.user?.displayId ?? m.userId)}</option>`).join("")}</select></label>`;
    } else if (action === "revoke") {
      fields = '<label>سبب السحب <input name="reason" class="form-input" required maxlength="1000"></label>';
    } else fields = '<label>المدة بالأيام <input name="days" type="number" class="form-input" min="1" max="365" step="1" value="30" required></label>';
    $("staffActionBox").hidden = false;
    $("staffActionBox").innerHTML = card(label, `<p>${person(r.user, r.userId)} · ${esc(roles[r.role])}</p><form id="staffActionForm" data-action="${action}" data-id="${id}" class="form-row">${fields}<button class="btn btn-primary">تأكيد ${label}</button>${button("cancelAction", "إلغاء")}</form>`);
    $("staffActionBox").scrollIntoView({ behavior: "smooth", block: "center" });
    $("staffActionBox").querySelector("input, select")?.focus();
  }
  const selection = (id) => [...$(id).querySelectorAll('input[type="checkbox"]:checked')].map(el => el.value);
  async function mutate(path, method, body) {
    if (!state.canWrite) throw new Error("التعديل متاح للمشرف الأعلى للمنصة فقط");
    await api(path, method, body);
    showToast("تم الحفظ بنجاح");
  }
  async function submit(form) {
    if (form.id === "staffFilters") return renderMembers();
    if (form.id === "staffAuditFilters") return loadAudit(1);
    if (form.id === "staffAppoint") {
      const id = Number(value("staffUserId"));
      if (!Number.isSafeInteger(id) || id < 1) throw new Error("معرّف المستخدم غير صالح");
      await mutate("/managers", "POST", { [value("staffIdKind")]: id, days: Number(value("staffDays")) });
      $("staffUserId").value = "";
    } else if (form.id === "staffActionForm") {
      const action = form.dataset.action;
      const body = action === "revoke" ? { reason: form.elements.reason.value.trim() } : action === "parent" ? { parentUserId: Number(form.elements.parentUserId.value) } : { days: Number(form.elements.days.value) };
      if (action === "revoke" && !body.reason) throw new Error("اكتب سبب السحب");
      await mutate(`/${form.dataset.id}/${action}`, "POST", body);
      $("staffActionBox").hidden = true;
    } else if (form.id === "staffPoolForm") {
      await mutate("/pool", "PUT", { itemIds: selection("staffPoolPicker") });
      await loadPool();
    } else if (form.dataset.staffRewards) {
      const role = form.dataset.staffRewards;
      await mutate("/role-rewards", "PUT", { [role]: selection(`staffReward_${role}`) });
      // Saving one role must not erase unsaved selections in other role pickers.
      state.rewards[role] = selection(`staffReward_${role}`);
    } else return;
    await loadMembers();
    await Promise.all([loadHolders(), loadGrants(), loadAudit(1), state.fileId ? openFile(state.fileId) : Promise.resolve()]);
  }
  const loaders = { staffMembers: loadMembers, staffPool: loadPool, staffRewards: loadRewards, staffHolders: loadHolders, staffGrants: loadGrants, staffBans: loadBans, staffAudit: () => loadAudit(state.page), staffFile: () => openFile(state.fileId) };
  async function run(key, task) {
    if (busy.has(key)) return;
    busy.add(key);
    const controls = typeof key === "object" ? [...key.querySelectorAll("button")] : [];
    controls.forEach(b => { b.disabled = true; });
    try { await task(); } catch (error) { showToast(errorText(error)); }
    finally { busy.delete(key); controls.forEach(b => { b.disabled = false; }); }
  }
  window.staffLoad = async function () {
    return run("load", async () => {
      state.canWrite = await ensureAdminRoleKnown();
      $("staffAccessNote").textContent = state.canWrite ? "يمكنك تعيين الـ Manager وإدارة التعيينات وقوائم المنتجات." : "وضع العرض فقط؛ التعديل متاح للمشرف الأعلى للمنصة.";
      $("staffAppoint").hidden = !state.canWrite;
      $("staffAppoint").querySelector("button").disabled = !state.canWrite;
      await loadMembers();
      await Promise.all([loadPool(), loadRewards(), loadHolders(), loadGrants(), loadBans(), loadAudit(1)]);
    });
  };
  init();
  $("staffRefresh").addEventListener("click", () => window.staffLoad());
  $("section-staff").addEventListener("submit", event => {
    event.preventDefault();
    const form = event.target;
    if (form.reportValidity()) run(form, () => submit(form));
  });
  $("section-staff").addEventListener("click", event => {
    const el = event.target.closest("[data-staff-action]");
    if (!el) return;
    const action = el.dataset.staffAction;
    const id = Number(el.dataset.id);
    if (action === "closeFile") { state.fileId = null; versions.staffFile = (versions.staffFile || 0) + 1; $("staffFile").hidden = true; }
    else if (action === "cancelAction") $("staffActionBox").hidden = true;
    else if (action === "file") run(el, () => openFile(id));
    else if (action === "page") run(el, () => loadAudit(id));
    else if (action === "retry") run(el, () => loaders[el.dataset.id]?.());
    else openAction(action, id);
  });
  $("section-staff").addEventListener("input", event => {
    const target = event.target.dataset.staffSearch;
    if (!target) return;
    const term = event.target.value.trim().toLocaleLowerCase();
    $(target).querySelectorAll("[data-item-search]").forEach(label => { label.style.display = label.dataset.itemSearch.includes(term) ? "flex" : "none"; });
  });
  $("section-staff").addEventListener("error", event => {
    if (event.target.matches?.("[data-staff-thumbnail]")) event.target.replaceWith(document.createTextNode("🖼️"));
  }, true);
})();
