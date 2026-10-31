// ============================================================
// لوحة التحكم — قوائم الإيموجي (طلب العميل 31/10)
//   إضافة وحذف قوائم، إضافة وحذف إيموجي (صورة أو GIF متحرك) مثل الهدايا.
//   القائمة: للجميع، أو لـ VIP من مستوى معين، أو لأشخاص محددين بالـ ID.
// Uses spec52Helpers / apiFetch from app.js + spec52-admin.js.
// ============================================================
(function () {
  "use strict";

  const { $, esc, toast, val, call } = window.spec52Helpers;
  const imgUrl = (u) => (typeof normalizeGiftImageUrl === "function" ? normalizeGiftImageUrl(u) : u);
  let lists = [];

  async function upload(file) {
    const fd = new FormData();
    fd.append("file", file);
    const d = await apiFetch("/admin/emoji/upload", { method: "POST", body: fd });
    if (!d?.url) throw new Error("لم يتم رفع الصورة");
    return d.url;
  }

  const accessLabel = (l) => {
    const parts = [];
    if (l.minVip > 0) parts.push(`VIP ${l.minVip}+`);
    if (l.users?.length) parts.push(`${l.users.length} شخص`);
    return parts.length ? parts.join(" أو ") : "الجميع";
  };

  async function emojiListsLoad() {
    const d = await call("/admin/emoji/lists");
    lists = d?.data || [];
    $("emojiLists").innerHTML =
      lists
        .map(
          (l) => `<div class="form-card" style="margin-top:12px">
        <div class="form-row" style="align-items:center">
          ${l.imageUrl ? `<img src="${esc(imgUrl(l.imageUrl))}" style="width:36px;height:36px;object-fit:contain">` : ""}
          <input class="form-input form-input--sm" id="el_name_${l.id}" value="${esc(l.nameAr)}" style="width:150px" title="اسم القائمة">
          <label class="cell-muted">الترتيب <input type="number" class="form-input form-input--sm" id="el_order_${l.id}" value="${Number(l.sortOrder) || 0}" style="width:70px"></label>
          <label class="cell-muted">مفعّلة <input type="checkbox" id="el_active_${l.id}" ${l.isActive ? "checked" : ""}></label>
          <label class="cell-muted">أقل VIP <input type="number" min="0" class="form-input form-input--sm" id="el_vip_${l.id}" value="${Number(l.minVip) || 0}" style="width:70px"></label>
          <input class="form-input form-input--sm" id="el_users_${l.id}" value="${esc((l.users || []).map((u) => u.displayId ?? "").filter(Boolean).join(", "))}" placeholder="IDs أشخاص (اختياري)" style="width:200px">
          <span class="badge">${esc(accessLabel(l))}</span>
          <input type="file" accept="image/*" style="display:none" id="el_icon_${l.id}" onchange="elIcon(${l.id})">
          <button class="btn btn-outline btn-sm" onclick="document.getElementById('el_icon_${l.id}').click()">صورة القائمة</button>
          <button class="btn btn-primary btn-sm" onclick="elSave(${l.id})">حفظ</button>
          <button class="btn btn-outline btn-sm" onclick="elDelete(${l.id}, ${l.emojis.length})">حذف القائمة</button>
        </div>
        <div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:10px">
          ${l.emojis
            .map(
              (e) => `<div style="width:92px;text-align:center;opacity:${e.isActive ? 1 : 0.4}">
            <img src="${esc(imgUrl(e.imageUrl))}" style="width:64px;height:64px;object-fit:contain">
            <div class="cell-muted" style="font-size:11px;overflow:hidden;white-space:nowrap">${esc(e.name || "—")}</div>
            <button class="btn btn-outline btn-sm" onclick="elToggleEmoji(${e.id}, ${!e.isActive})">${e.isActive ? "إخفاء" : "إظهار"}</button>
            <button class="btn btn-outline btn-sm" onclick="elDeleteEmoji(${e.id})">حذف</button>
          </div>`,
            )
            .join("")}
          <div style="width:92px;text-align:center">
            <input type="file" accept="image/*" multiple style="display:none" id="el_add_${l.id}" onchange="elAddEmoji(${l.id})">
            <button class="btn btn-primary btn-sm" style="width:64px;height:64px;font-size:26px" onclick="document.getElementById('el_add_${l.id}').click()" title="إضافة إيموجي (PNG / WebP / GIF)">+</button>
            <div class="cell-muted" style="font-size:11px">إضافة إيموجي</div>
          </div>
        </div>
      </div>`,
        )
        .join("") || '<p class="cell-muted" style="margin-top:12px">لا توجد قوائم بعد — أضف قائمة ثم ارفع الإيموجي.</p>';
  }

  const warnMissing = (d) => {
    if (d?.missing?.length) toast("⚠️ IDs غير موجودة: " + d.missing.join(", "));
  };

  async function elAdd() {
    const nameAr = val("el_new_name");
    if (!nameAr) return toast("اكتب اسم القائمة");
    const d = await call("/admin/emoji/lists", "POST", { nameAr, minVip: Number(val("el_new_vip") || 0), userIds: val("el_new_users") });
    warnMissing(d);
    ["el_new_name", "el_new_vip", "el_new_users"].forEach((id) => ($(id).value = ""));
    toast("✅ تمت إضافة القائمة");
    emojiListsLoad();
  }

  async function elSave(id) {
    const d = await call(`/admin/emoji/lists/${id}`, "PATCH", {
      nameAr: val(`el_name_${id}`),
      sortOrder: Number(val(`el_order_${id}`) || 0),
      isActive: $(`el_active_${id}`).checked,
      minVip: Number(val(`el_vip_${id}`) || 0),
      userIds: val(`el_users_${id}`),
    });
    warnMissing(d);
    toast("✅ تم الحفظ");
    emojiListsLoad();
  }

  async function elIcon(id) {
    const file = $(`el_icon_${id}`)?.files?.[0];
    if (!file) return;
    await call(`/admin/emoji/lists/${id}`, "PATCH", { imageUrl: await upload(file) });
    toast("✅ تم تغيير صورة القائمة");
    emojiListsLoad();
  }

  async function elDelete(id, count) {
    if (!confirm(count ? `حذف القائمة و ${count} إيموجي بداخلها؟` : "حذف القائمة؟")) return;
    await call(`/admin/emoji/lists/${id}`, "DELETE");
    toast("✅ تم حذف القائمة");
    emojiListsLoad();
  }

  async function elAddEmoji(listId) {
    const files = [...($(`el_add_${listId}`)?.files || [])];
    for (const file of files) {
      const url = await upload(file);
      await call(`/admin/emoji/lists/${listId}/emojis`, "POST", { imageUrl: url, name: file.name.replace(/\.[^.]+$/, "") });
    }
    if (files.length) toast(`✅ تمت إضافة ${files.length} إيموجي`);
    emojiListsLoad();
  }

  async function elToggleEmoji(id, isActive) {
    await call(`/admin/emoji/emojis/${id}`, "PATCH", { isActive });
    emojiListsLoad();
  }

  async function elDeleteEmoji(id) {
    if (!confirm("حذف هذا الإيموجي؟")) return;
    await call(`/admin/emoji/emojis/${id}`, "DELETE");
    toast("✅ تم الحذف");
    emojiListsLoad();
  }

  Object.assign(window, { emojiListsLoad, elAdd, elSave, elIcon, elDelete, elAddEmoji, elToggleEmoji, elDeleteEmoji });
  window.spec52Register("emojilists", emojiListsLoad);
})();
