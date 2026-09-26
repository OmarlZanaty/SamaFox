// ============================================================
// لوحة التحكم — صفحات 2026-09-26
//   اقتصاد الألعاب · إدارة المحظوظ · CP (رسوم الفك، المستويات، التأثيرات)
//   منح المميزات · Target المضيف · سجل المراجعة · نوع الغرفة
// Uses apiFetch / showToast / escapeHtml from app.js. Every write sends a
// `reason`, which the server stores in admin_audit_logs.
// ============================================================
(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const n = (v) => Number(v || 0).toLocaleString("en-US");
  const pct = (v) => (v == null || !Number.isFinite(Number(v)) ? "—" : (Number(v) * 100).toFixed(2) + "%");
  const bpToPct = (bp) => (bp == null ? "" : (Number(bp) / 100).toString());
  const pctToBp = (p) => (p === "" || p == null ? null : Math.round(Number(p) * 100));
  const esc = (s) => (typeof escapeHtml === "function" ? escapeHtml(String(s ?? "")) : String(s ?? ""));
  const toast = (m) => (typeof showToast === "function" ? showToast(m) : alert(m));
  const val = (id) => ($(id)?.value ?? "").trim();
  const intOrEmpty = (id) => (val(id) === "" ? null : Math.floor(Number(val(id))));
  const dayStr = (d) => (d ? new Date(d).toISOString().slice(0, 10) : "");
  const dt = (d) => (d ? new Date(d).toLocaleString("en-GB") : "—");
  const LABELS = (typeof GAME_LABELS !== "undefined" && GAME_LABELS) || {};

  function reasonFrom(id) {
    const r = val(id);
    if (r.length < 3) {
      toast("اكتب سبب التعديل أولاً (يُحفظ في سجل المراجعة)");
      $(id)?.focus();
      return null;
    }
    return r;
  }

  async function call(path, method, body) {
    try {
      return await apiFetch(path, method || "GET", body);
    } catch (e) {
      toast("❌ " + (e?.message || "فشل"));
      throw e;
    }
  }

  function userCardHtml(u) {
    if (!u) return "";
    const status = u.accountStatus === "BANNED" ? '<span class="badge badge-rejected">محظور</span>' : '<span class="badge badge-approved">نشط</span>';
    return `<div style="display:flex;gap:12px;align-items:center">
      <img src="${esc(u.avatarUrl || "")}" onerror="this.style.visibility='hidden'" style="width:56px;height:56px;border-radius:50%;object-fit:cover;border:1px solid var(--card-border)" />
      <div><div style="font-weight:800">${esc(u.name || "—")}</div>
      <div class="cell-muted">ID: ${esc(u.displayId ?? u.id)} · الرصيد ${n(u.coinsBalance)} · LV ${esc(u.level ?? "")} · VIP ${esc(u.vipLevel ?? 0)}</div>
      <div>${status}</div></div></div>`;
  }

  // ═══════════════════ اقتصاد الألعاب ═══════════════════
  let econData = null;
  let econGame = null;

  async function econLoadGames() {
    const q = new URLSearchParams();
    if (val("econ_from")) q.set("from", val("econ_from"));
    if (val("econ_to")) q.set("to", new Date(new Date(val("econ_to")).getTime() + 86_400_000).toISOString().slice(0, 10));
    const res = await call("/admin-dashboard/games-economy?" + q.toString());
    econData = res?.data;
    const t = econData?.totals || {};
    $("econTotals").innerHTML = [
      ["إجمالي اللعب", n(t.totalBets)],
      ["إجمالي المكاسب", n(t.totalPayouts)],
      ["إجمالي حصة البرنامج", n(t.programShare)],
      ["إجمالي صندوق اللاعبين", n(t.playerPrizePool)],
      ["إجمالي صافي النتيجة", n(t.netResult)],
      ["أرصدة صناديق الألعاب الآن", n(t.poolBalance)],
      ["حساب البرنامج", n(t.programAccount)],
      ["الجولات", n(t.rounds)],
    ].map(([k, v]) => `<div class="stat-card"><div class="stat-label">${k}</div><div class="stat-value">${v}</div></div>`).join("");
    const rows = econData?.games || [];
    document.querySelector("#econGamesTable tbody").innerHTML = rows.map((g) => {
      const warn = g.rtpActual != null && g.rtpTarget != null && g.rtpActual > g.rtpTarget ? ' style="color:#ff7070;font-weight:800"' : "";
      return `<tr>
        <td><strong>${esc(LABELS[g.game] || g.game)}</strong><div class="cell-muted">${esc(g.game)}</div></td>
        <td>${g.settings.enabled ? "تعمل" : "متوقفة"}</td>
        <td>${n(g.totalBets)}</td><td>${n(g.totalPayouts)}</td><td>${n(g.programShare)}</td><td>${n(g.playerPrizePool)}</td>
        <td>${n(g.netResult)}</td><td>${n(g.rounds)}</td><td>${n(g.players)}</td><td>${n(g.highestWin)}</td><td>${n(g.averageWin)}</td>
        <td${warn}>${pct(g.rtpActual)}</td><td>${pct(g.rtpTarget)}</td><td>${pct(g.lossRatio)}</td>
        <td>${n(g.profitLoss)}</td><td>${n(g.poolBalance)}${g.poolReserved ? `<div class="cell-muted">محجوز ${n(g.poolReserved)}</div>` : ""}</td>
        <td><button class="btn btn-outline btn-sm" onclick="econEdit('${esc(g.game)}')">تعديل</button></td>
      </tr>`;
    }).join("");
    if (econGame) econEdit(econGame);
  }

  function econEdit(game) {
    const g = (econData?.games || []).find((x) => x.game === game);
    if (!g) return;
    econGame = game;
    const s = g.settings;
    $("econEditCard").style.display = "";
    $("econEditTitle").textContent = LABELS[game] || game;
    $("econ_enabled").value = s.enabled ? "1" : "0";
    $("econ_minBet").value = s.minBet ?? "";
    $("econ_maxBet").value = s.maxBet ?? "";
    $("econ_maxWinPerRound").value = s.maxWinPerRound ?? "";
    $("econ_dailyMaxWinPerUser").value = s.dailyMaxWinPerUser ?? "";
    $("econ_maxPayoutRatio").value = s.maxPayoutRatio ?? "";
    $("econ_rtpTarget").value = bpToPct(s.rtpTargetBp);
    $("econ_programShare").value = bpToPct(s.programShareBp);
    $("econNatural").textContent =
      `أعلى مضاعف طبيعي للعبة: ×${g.naturalMaxMultiplier ?? "—"} — نسبة دفع أقل منه تقص المكاسب الكبيرة. ` +
      `صندوق اللاعبين يأخذ ${(100 - Number(s.programShareBp) / 100).toFixed(2)}% من كل رهان، فـ RTP المستهدف يجب ألا يتجاوزها.`;
    $("econEditCard").scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function econSaveGame() {
    if (!econGame) return;
    const reason = reasonFrom("econ_reason");
    if (!reason) return;
    await call(`/admin-dashboard/games-economy/${encodeURIComponent(econGame)}`, "PATCH", {
      enabled: val("econ_enabled") === "1",
      minBet: intOrEmpty("econ_minBet"),
      maxBet: intOrEmpty("econ_maxBet"),
      maxWinPerRound: intOrEmpty("econ_maxWinPerRound"),
      dailyMaxWinPerUser: intOrEmpty("econ_dailyMaxWinPerUser"),
      maxPayoutRatio: intOrEmpty("econ_maxPayoutRatio"),
      rtpTargetBp: pctToBp(val("econ_rtpTarget")),
      programShareBp: pctToBp(val("econ_programShare")),
      reason,
    });
    $("econ_reason").value = "";
    toast("✅ تم الحفظ");
    econLoadGames().catch(() => {});
  }

  async function econFundGame() {
    if (!econGame) return;
    const amount = intOrEmpty("econ_fund");
    if (!amount || amount <= 0) return toast("اكتب مبلغ التمويل");
    const reason = reasonFrom("econ_reason");
    if (!reason) return;
    if (!confirm(`تمويل صندوق ${LABELS[econGame] || econGame} بـ ${n(amount)} من حساب البرنامج؟`)) return;
    const r = await call(`/admin-dashboard/games-economy/${encodeURIComponent(econGame)}/fund`, "POST", { amount, reason });
    $("econ_fund").value = "";
    toast(`✅ رصيد الصندوق الآن ${n(r?.data?.poolBalance)}`);
    econLoadGames().catch(() => {});
  }

  // ═══════════════════ إدارة المحظوظ ═══════════════════
  let lkCfg = null;
  let lkTiers = [];

  async function lkLoad() {
    const q = new URLSearchParams();
    if (val("lk_from")) q.set("from", val("lk_from"));
    if (val("lk_to")) q.set("to", new Date(new Date(val("lk_to")).getTime() + 86_400_000).toISOString().slice(0, 10));
    const res = await call("/admin-dashboard/lucky-mgmt?" + q.toString());
    const d = res?.data || {};
    lkCfg = d.config;
    const c = d.config || {};
    $("lk_enabled").value = c.enabled ? "1" : "0";
    $("lk_programShare").value = bpToPct(c.programShareBp);
    $("lk_prizePool").value = bpToPct(c.prizePoolBp);
    $("lk_hostShare").value = bpToPct(c.hostShareBp);
    $("lk_minPlayers").value = c.minPlayers ?? "";
    $("lk_maxPlayers").value = c.maxPlayers ?? "";
    $("lk_minEntry").value = c.minEntry ?? "";
    $("lk_maxEntry").value = c.maxEntry ?? "";
    $("lk_rtp").value = bpToPct(c.rtpTargetBp);
    $("lk_maxWin").value = c.maxWin ?? "";
    $("lk_roundSeconds").value = c.roundSeconds ?? "";
    $("lk_broadcastMin").value = c.broadcastMin ?? "";

    const r = d.report || {};
    $("lkStats").innerHTML = [
      ["صندوق المحظوظ الآن", n(d.pool?.balance)],
      ["إجمالي المشاركات", n(r.totalEntry)],
      ["حصة البرنامج (صافي)", n(r.programShare)],
      ["حصة المضيفين", n(r.hostShare)],
      ["صندوق الجوائز (70%)", n(r.prizePool)],
      ["إجمالي المكاسب", n(r.totalWin)],
      ["RTP فعلي", pct(r.rtpActual)],
      ["أعلى مكسب", n(r.highestWin)],
      ["لاعبين / مشاركات", `${n(r.players)} / ${n(r.entries)}`],
      ["بانتظار لاعب آخر", n(r.pending)],
      ["بدون منافسة", n(r.noCompetition)],
      ["جولات مكتملة / غير تنافسية", `${n(r.rounds?.SETTLED)} / ${n(r.rounds?.NOT_COMPETITIVE)}`],
    ].map(([k, v]) => `<div class="stat-card"><div class="stat-label">${k}</div><div class="stat-value">${v}</div></div>`).join("");

    const byM = new Map((d.tiers || []).map((t) => [t.multiplier, t]));
    lkTiers = (d.multipliers || []).map((m) => byM.get(m) || { multiplier: m, weightBp: 0, minPoolCoins: 0, isActive: true });
    document.querySelector("#lkTiersTable tbody").innerHTML = lkTiers.map((t, i) => `
      <tr>
        <td><strong>x${t.multiplier}</strong></td>
        <td><input id="lkt_w_${i}" type="number" min="0" max="100" step="0.01" class="form-input form-input--sm" value="${(Number(t.weightBp) / 100).toString()}" oninput="lkAnalyze()" /></td>
        <td id="lkt_c_${i}" class="cell-muted"></td>
        <td><input id="lkt_m_${i}" type="number" min="0" class="form-input form-input--sm" value="${Number(t.minPoolCoins || 0)}" /></td>
        <td><input id="lkt_a_${i}" type="checkbox" ${t.isActive ? "checked" : ""} onchange="lkAnalyze()" /></td>
      </tr>`).join("");
    lkAnalyze();
    lkSearch(1).catch(() => {});
  }

  function lkReadTiers() {
    return lkTiers.map((t, i) => ({
      multiplier: t.multiplier,
      weightBp: Math.round(Number($(`lkt_w_${i}`).value || 0) * 100),
      minPoolCoins: Math.max(0, Math.floor(Number($(`lkt_m_${i}`).value || 0))),
      isActive: $(`lkt_a_${i}`).checked,
    }));
  }

  function lkAnalyze() {
    const tiers = lkReadTiers();
    const hostShare = (pctToBp(val("lk_hostShare")) ?? lkCfg?.hostShareBp ?? 1000) / 10_000;
    const rtpTarget = (pctToBp(val("lk_rtp")) ?? lkCfg?.rtpTargetBp ?? 6500) / 10_000;
    let total = 0;
    let em = 0;
    tiers.forEach((t, i) => {
      const w = t.isActive ? t.weightBp : 0;
      total += w;
      em += (t.multiplier * w) / 10_000;
      const cell = $(`lkt_c_${i}`);
      if (cell) cell.textContent = ((t.multiplier * w) / 10_000 * hostShare * 100).toFixed(2) + "%";
    });
    const rtp = em * hostShare;
    const okSum = total <= 10_000;
    const okRtp = rtp <= rtpTarget + 1e-9;
    $("lkAnalysis").innerHTML =
      `مجموع الاحتمالات <strong style="color:${okSum ? "inherit" : "#ff7070"}">${(total / 100).toFixed(2)}%</strong> · ` +
      `بدون مكسب ${((10_000 - total) / 100).toFixed(2)}% · E[المضاعف] ${em.toFixed(2)} · ` +
      `RTP المحسوب <strong style="color:${okRtp ? "inherit" : "#ff7070"}">${(rtp * 100).toFixed(2)}%</strong> (المستهدف ${(rtpTarget * 100).toFixed(2)}%)` +
      (okSum && okRtp ? "" : ' — <strong style="color:#ff7070">لن يُحفظ</strong>');
  }

  async function lkSaveSettings() {
    const reason = reasonFrom("lk_reason");
    if (!reason) return;
    await call("/admin-dashboard/lucky-mgmt/settings", "PATCH", {
      enabled: val("lk_enabled") === "1",
      programShareBp: pctToBp(val("lk_programShare")),
      prizePoolBp: pctToBp(val("lk_prizePool")),
      hostShareBp: pctToBp(val("lk_hostShare")),
      minPlayers: intOrEmpty("lk_minPlayers"),
      maxPlayers: intOrEmpty("lk_maxPlayers"),
      minEntry: intOrEmpty("lk_minEntry"),
      maxEntry: intOrEmpty("lk_maxEntry"),
      rtpTargetBp: pctToBp(val("lk_rtp")),
      maxWin: intOrEmpty("lk_maxWin"),
      roundSeconds: intOrEmpty("lk_roundSeconds"),
      broadcastMin: intOrEmpty("lk_broadcastMin"),
      reason,
    });
    $("lk_reason").value = "";
    toast("✅ تم حفظ إعدادات المحظوظ");
    lkLoad().catch(() => {});
  }

  async function lkSaveTiers() {
    const reason = reasonFrom("lk_tiers_reason");
    if (!reason) return;
    await call("/admin-dashboard/lucky-mgmt/tiers", "PUT", { tiers: lkReadTiers(), reason });
    $("lk_tiers_reason").value = "";
    toast("✅ تم حفظ الاحتمالات");
    lkLoad().catch(() => {});
  }

  async function lkFund() {
    const amount = intOrEmpty("lk_fund");
    if (!amount || amount <= 0) return toast("اكتب المبلغ");
    const reason = reasonFrom("lk_tiers_reason");
    if (!reason) return;
    if (!confirm(`تمويل صندوق المحظوظ بـ ${n(amount)} من حساب البرنامج؟`)) return;
    const r = await call("/admin-dashboard/lucky-mgmt/fund", "POST", { amount, reason });
    $("lk_fund").value = "";
    toast(`✅ الصندوق الآن ${n(r?.data?.poolBalance)}`);
    lkLoad().catch(() => {});
  }

  const LK_STATUS = { PENDING: "بانتظار لاعب", SETTLED: "تمت", NO_COMPETITION: "بدون منافسة" };
  let lkPage = 1;
  async function lkSearch(page) {
    lkPage = page || 1;
    const q = new URLSearchParams({ page: String(lkPage) });
    if (val("lkq_user")) q.set("user", val("lkq_user"));
    if (val("lkq_room")) q.set("room", val("lkq_room"));
    if (val("lkq_round")) q.set("round", val("lkq_round"));
    if (val("lkq_from")) q.set("from", val("lkq_from"));
    if (val("lkq_to")) q.set("to", new Date(new Date(val("lkq_to")).getTime() + 86_400_000).toISOString().slice(0, 10));
    const res = await call("/admin-dashboard/lucky-mgmt/log?" + q.toString());
    const d = res?.data || { rows: [] };
    document.querySelector("#lkLogTable tbody").innerHTML = d.rows.map((r) => {
      const at = new Date(r.createdAt);
      return `<tr>
        <td>${esc(r.roundCode || "—")}${r.roundPlayers != null ? `<div class="cell-muted">${r.roundPlayers} لاعب</div>` : ""}</td>
        <td>${esc(r.roomId ?? "—")}<div class="cell-muted">${esc(r.roomName || "")}</div></td>
        <td>${esc(r.player?.name || "")}<div class="cell-muted">ID ${esc(r.player?.displayId ?? r.player?.id)}</div></td>
        <td>${n(r.totalEntry)}</td><td>${n(r.hostShare)}</td><td>${n(r.programShare)}</td><td>${n(r.prizePool)}</td>
        <td>${r.multiplier ? "x" + r.multiplier : "—"}</td><td>${n(r.win)}</td>
        <td>${LK_STATUS[r.status] || esc(r.status)}</td>
        <td>${at.toLocaleDateString("en-GB")}</td><td>${at.toLocaleTimeString("en-GB")}</td>
      </tr>`;
    }).join("");
    const pages = Math.max(1, Math.ceil(d.total / d.pageSize));
    $("lkLogMeta").innerHTML = `${n(d.total)} سجل · صفحة ${d.page} من ${pages} ` +
      (d.page > 1 ? `<button class="btn btn-outline btn-sm" onclick="lkSearch(${d.page - 1})">السابق</button>` : "") +
      (d.page < pages ? `<button class="btn btn-outline btn-sm" onclick="lkSearch(${d.page + 1})">التالي</button>` : "");
  }

  // ═══════════════════ CP ═══════════════════
  let cpcUserId = null;
  let cplRows = [];
  let cpeRows = [];

  async function cpEconLoad() {
    const [fees, lv] = await Promise.all([
      call("/admin-dashboard/cp-economy/break-fees"),
      call("/admin-dashboard/cp-economy/levels"),
    ]);
    $("cpb_program").value = fees?.data?.programFee ?? 0;
    $("cpb_partner").value = fees?.data?.partnerFee ?? 0;
    cpbTotal();
    cplRows = lv?.data?.levels || [];
    cpeRows = lv?.data?.effects || [];
    cplRender();
    cpeRender();
    cpblLoad().catch(() => {});
  }

  function cpbTotal() {
    $("cpb_total").value = n(Number(val("cpb_program") || 0) + Number(val("cpb_partner") || 0));
  }

  async function cpbSave() {
    const reason = reasonFrom("cpb_reason");
    if (!reason) return;
    await call("/admin-dashboard/cp-economy/break-fees", "PUT", {
      programFee: Number(val("cpb_program") || 0),
      partnerFee: Number(val("cpb_partner") || 0),
      reason,
    });
    $("cpb_reason").value = "";
    toast("✅ تم حفظ رسوم فك CP");
  }

  async function cpcSearch() {
    const ref = val("cpc_user");
    if (!ref) return;
    const res = await call(`/admin-dashboard/cp-economy/custom-fee/${encodeURIComponent(ref)}`);
    const d = res?.data;
    cpcUserId = d?.user?.id ?? null;
    const partners = (d?.partners || []).map((p) =>
      `<li>${esc(p.partner?.name)} (ID ${esc(p.partner?.displayId ?? p.partner?.id)}) · LV ${esc(p.level)} · قيمة ${n(p.cpValue)} · منذ ${dayStr(p.since)}</li>`,
    ).join("");
    $("cpcCard").innerHTML = userCardHtml(d?.user) +
      `<div class="cell-muted" style="margin-top:8px">CP الحالي:</div><ul style="margin:4px 16px">${partners || "<li>لا يوجد</li>"}</ul>` +
      `<div class="cell-muted">الرسوم العامة: برنامج ${n(d?.global?.programFee)} + شريك ${n(d?.global?.partnerFee)}</div>`;
    $("cpc_program").value = d?.custom ? Number(d.custom.programFee) : "";
    $("cpc_partner").value = d?.custom ? Number(d.custom.partnerFee) : "";
    $("cpc_enabled").checked = Boolean(d?.custom?.enabled);
  }

  async function cpcSave() {
    if (!cpcUserId) return toast("ابحث عن المستخدم أولاً");
    const reason = reasonFrom("cpc_reason");
    if (!reason) return;
    await call(`/admin-dashboard/cp-economy/custom-fee/${cpcUserId}`, "PUT", {
      programFee: Number(val("cpc_program") || 0),
      partnerFee: Number(val("cpc_partner") || 0),
      enabled: $("cpc_enabled").checked,
      reason,
    });
    $("cpc_reason").value = "";
    toast("✅ تم حفظ الرسوم المخصصة");
  }

  function cplRender() {
    const effectOpts = (sel) => ['<option value="">—</option>'].concat(cpeRows.map((e) =>
      `<option value="${esc(e.effectKey)}" ${e.effectKey === sel ? "selected" : ""}>${esc(e.effectKey)}</option>`)).join("");
    document.querySelector("#cplTable tbody").innerHTML = cplRows.map((l) => `
      <tr>
        <td><strong>${l.level}</strong></td>
        <td><input id="cpl_req_${l.level}" type="number" min="0" class="form-input form-input--sm" value="${Number(l.requiredCoins)}" /></td>
        <td><input id="cpl_name_${l.level}" class="form-input form-input--sm" value="${esc(l.name || "")}" /></td>
        <td><input id="cpl_badge_${l.level}" class="form-input form-input--sm" value="${esc(l.badgeUrl || "")}" placeholder="رابط الشارة" /></td>
        <td><input id="cpl_frame_${l.level}" class="form-input form-input--sm" value="${esc(l.frameUrl || "")}" placeholder="رابط الإطار" /></td>
        <td><select id="cpl_fx_${l.level}" class="form-input form-input--sm">${effectOpts(l.effectKey)}</select></td>
        <td><input id="cpl_en_${l.level}" type="checkbox" ${l.enabled ? "checked" : ""} /></td>
        <td style="white-space:nowrap"><button class="btn btn-primary btn-sm" onclick="cplSave(${l.level})">حفظ</button>
            <button class="btn btn-outline btn-sm" onclick="cplDelete(${l.level})">حذف</button></td>
      </tr>`).join("");
  }

  function cplAddRow() {
    const lv = intOrEmpty("cpl_new_level");
    if (!lv || lv < 1) return toast("اكتب رقم المستوى");
    if (cplRows.some((l) => l.level === lv)) return toast("المستوى موجود");
    cplRows.push({ level: lv, requiredCoins: 0, enabled: true });
    cplRows.sort((a, b) => a.level - b.level);
    cplRender();
  }

  async function cplSave(level) {
    const reason = prompt("سبب التعديل (يُحفظ في سجل المراجعة):");
    if (!reason || reason.trim().length < 3) return toast("السبب مطلوب");
    await call(`/admin-dashboard/cp-economy/levels/${level}`, "PUT", {
      requiredCoins: Number(val(`cpl_req_${level}`) || 0),
      name: val(`cpl_name_${level}`),
      badgeUrl: val(`cpl_badge_${level}`),
      frameUrl: val(`cpl_frame_${level}`),
      effectKey: val(`cpl_fx_${level}`),
      enabled: $(`cpl_en_${level}`).checked,
      reason,
    });
    toast("✅ تم حفظ المستوى " + level);
    cpEconLoad().catch(() => {});
  }

  async function cplDelete(level) {
    if (!cplRows.find((l) => l.level === level)?.updatedAt) {
      cplRows = cplRows.filter((l) => l.level !== level);
      return cplRender();
    }
    const reason = prompt(`حذف المستوى ${level}؟ اكتب السبب:`);
    if (!reason || reason.trim().length < 3) return;
    await call(`/admin-dashboard/cp-economy/levels/${level}`, "DELETE", { reason });
    toast("✅ تم الحذف");
    cpEconLoad().catch(() => {});
  }

  function cpeRender() {
    document.querySelector("#cpeTable tbody").innerHTML = cpeRows.map((e) => `
      <tr>
        <td><strong>${esc(e.effectKey)}</strong></td>
        <td><input id="cpe_name_${esc(e.effectKey)}" class="form-input form-input--sm" value="${esc(e.name || "")}" /></td>
        <td><input id="cpe_lv_${esc(e.effectKey)}" type="number" min="0" class="form-input form-input--sm" value="${e.requiredLevel}" /></td>
        <td><input id="cpe_en_${esc(e.effectKey)}" type="checkbox" ${e.enabled ? "checked" : ""} /></td>
        <td><input id="cpe_dur_${esc(e.effectKey)}" type="number" min="0" class="form-input form-input--sm" value="${e.durationSec}" /></td>
        <td><input id="cpe_spd_${esc(e.effectKey)}" type="number" min="0.25" max="4" step="0.25" class="form-input form-input--sm" value="${e.animationSpeed}" /></td>
        <td><input id="cpe_pr_${esc(e.effectKey)}" type="number" class="form-input form-input--sm" value="${e.priority}" /></td>
        <td><button class="btn btn-primary btn-sm" onclick="cpeSave('${esc(e.effectKey)}')">حفظ</button></td>
      </tr>`).join("");
  }

  async function cpeSave(key) {
    const reason = prompt("سبب التعديل (يُحفظ في سجل المراجعة):");
    if (!reason || reason.trim().length < 3) return toast("السبب مطلوب");
    await call(`/admin-dashboard/cp-economy/effects/${encodeURIComponent(key)}`, "PUT", {
      name: val(`cpe_name_${key}`),
      requiredLevel: Number(val(`cpe_lv_${key}`) || 1),
      enabled: $(`cpe_en_${key}`).checked,
      durationSec: Number(val(`cpe_dur_${key}`) || 0),
      animationSpeed: Number(val(`cpe_spd_${key}`) || 1),
      priority: Number(val(`cpe_pr_${key}`) || 0),
      reason,
    });
    toast("✅ تم حفظ التأثير");
    cpEconLoad().catch(() => {});
  }

  async function cpblLoad() {
    const q = val("cpbl_user") ? "?user=" + encodeURIComponent(val("cpbl_user")) : "";
    const res = await call("/admin-dashboard/cp-economy/break-logs" + q);
    document.querySelector("#cpblTable tbody").innerHTML = (res?.data || []).map((r) => `
      <tr><td>${r.id}</td>
        <td>${esc(r.requester?.name || "")}<div class="cell-muted">ID ${esc(r.requester?.displayId ?? r.requesterId)}</div></td>
        <td>${esc(r.partner?.name || "")}<div class="cell-muted">ID ${esc(r.partner?.displayId ?? r.partnerId)}</div></td>
        <td>${n(r.programFee)}</td><td>${n(r.partnerFee)}</td><td>${esc(r.feeSource)}</td><td>${n(r.cpValue)}</td><td>${dt(r.createdAt)}</td>
      </tr>`).join("");
  }

  // ═══════════════════ منح المميزات ═══════════════════
  let ftUserId = null;

  function ftInit() {}

  async function ftSearch() {
    const ref = val("ft_user");
    if (!ref) return;
    const res = await call(`/admin-dashboard/features/user/${encodeURIComponent(ref)}`);
    ftUserId = res?.data?.user?.id ?? null;
    $("ftUserCard").innerHTML = userCardHtml(res?.data?.user);
    ftRender(res?.data?.features || []);
  }

  function ftRender(list) {
    document.querySelector("#ftTable tbody").innerHTML = list.map((f) => `
      <tr>
        <td><strong>${esc(f.nameAr)}</strong><div class="cell-muted">${esc(f.key)} · ${f.kind === "permission" ? "صلاحية" : "ميزة"}</div></td>
        <td class="cell-muted" style="max-width:360px">${esc(f.description)}</td>
        <td>${f.granted ? '<span class="badge badge-approved">ممنوحة</span>' : '<span class="badge badge-pending">غير ممنوحة</span>'}</td>
        <td>${f.userToggle ? (f.userOn ? "ON" : "OFF") : "—"}</td>
        <td>${f.expiresAt ? dt(f.expiresAt) : "—"}</td>
        <td style="white-space:nowrap">
          ${f.granted
            ? `<button class="btn btn-outline btn-sm" onclick="ftRevoke('${esc(f.key)}')">سحب</button>`
            : `<input id="ft_exp_${esc(f.key)}" type="date" class="form-input form-input--sm" title="ينتهي (اختياري)" />
               <button class="btn btn-primary btn-sm" onclick="ftGrant('${esc(f.key)}')">منح</button>`}
        </td>
      </tr>`).join("");
  }

  async function ftGrant(key) {
    if (!ftUserId) return;
    const reason = prompt("سبب المنح (يُحفظ في سجل المراجعة):");
    if (!reason || reason.trim().length < 3) return toast("السبب مطلوب");
    const exp = val(`ft_exp_${key}`);
    const res = await call(`/admin-dashboard/features/user/${ftUserId}/grant`, "POST", {
      key,
      expiresAt: exp ? new Date(exp + "T23:59:59").toISOString() : null,
      reason,
    });
    ftRender(res?.data || []);
    toast("✅ تم المنح");
  }

  async function ftRevoke(key) {
    if (!ftUserId) return;
    const reason = prompt("سبب السحب (يُحفظ في سجل المراجعة):");
    if (!reason || reason.trim().length < 3) return toast("السبب مطلوب");
    const res = await call(`/admin-dashboard/features/user/${ftUserId}/revoke`, "POST", { key, reason });
    ftRender(res?.data || []);
    toast("✅ تم السحب");
  }

  async function ftEntries() {
    const q = new URLSearchParams();
    if (val("fte_user")) q.set("user", val("fte_user"));
    if (val("fte_room")) q.set("room", val("fte_room"));
    if ($("fte_hidden").checked) q.set("hiddenOnly", "1");
    const res = await call("/admin-dashboard/features/room-entries?" + q.toString());
    document.querySelector("#ftEntriesTable tbody").innerHTML = (res?.data || []).map((r) => `
      <tr>
        <td>${esc(r.user?.name || "")}<div class="cell-muted">ID ${esc(r.user?.displayId ?? r.userId)}</div></td>
        <td>${esc(r.roomId)}<div class="cell-muted">${esc(r.room?.name || "")}</div></td>
        <td>${r.hidden ? "نعم" : "لا"}</td><td>${esc(r.lockBypass || "—")}</td>
        <td>${dt(r.enteredAt)}</td><td>${r.exitedAt ? dt(r.exitedAt) : '<span class="badge badge-approved">داخل الآن</span>'}</td>
      </tr>`).join("");
  }

  // ═══════════════════ Target المضيف ═══════════════════
  let tgHostId = null;

  async function tgSearch() {
    const ref = val("tg_user");
    if (!ref) return;
    const res = await call(`/admin-dashboard/host-targets/user/${encodeURIComponent(ref)}`);
    const d = res?.data;
    tgHostId = d?.user?.id ?? null;
    $("tgUserCard").innerHTML = userCardHtml(d?.user);
    const a = d?.active;
    $("tgActive").innerHTML = a
      ? `التارجت الحالي: <strong>${n(a.targetCoins)}</strong> كوينز / <strong>$${Number(a.targetUsd).toFixed(2)}</strong> · ` +
        `من ${dayStr(a.periodStart)} إلى ${dayStr(a.periodEnd)} · تم تحقيق ${n(a.earnedCoins)} (${(a.progress * 100).toFixed(1)}%) · المتبقي ${n(a.remainingCoins)} · Version ${a.version}`
      : "لا يوجد تارجت فعّال الآن.";
    const today = new Date();
    if (!val("tg_start")) $("tg_start").value = dayStr(today);
    if (!val("tg_end")) $("tg_end").value = dayStr(new Date(today.getTime() + 30 * 86_400_000));
    document.querySelector("#tgHistory tbody").innerHTML = (d?.history || []).map((t) => `
      <tr><td>${t.id}</td><td>${n(t.targetCoins)}</td><td>$${Number(t.targetUsd).toFixed(2)}</td>
        <td>${dayStr(t.periodStart)}</td><td>${dayStr(t.periodEnd)}</td><td>${esc(t.status)}</td><td>${esc(t.source)}</td>
        <td>${t.version}</td><td>${dt(t.updatedAt)}</td>
        <td>${t.status === "ACTIVE" ? `<button class="btn btn-outline btn-sm" onclick="tgCancel(${t.id})">إلغاء</button>` : ""}</td></tr>`).join("");
  }

  async function tgSave() {
    if (!tgHostId) return toast("ابحث عن المضيف أولاً");
    const reason = reasonFrom("tg_reason");
    if (!reason) return;
    await call("/admin-dashboard/host-targets", "POST", {
      hostId: tgHostId,
      targetCoins: Number(val("tg_coins") || 0),
      targetUsd: Number(val("tg_usd") || 0),
      periodStart: new Date(val("tg_start") + "T00:00:00").toISOString(),
      periodEnd: new Date(val("tg_end") + "T23:59:59").toISOString(),
      note: val("tg_note") || null,
      reason,
    });
    $("tg_reason").value = "";
    toast("✅ تم حفظ التارجت");
    tgSearch().catch(() => {});
  }

  async function tgCancel(id) {
    const reason = prompt("سبب الإلغاء:");
    if (!reason || reason.trim().length < 3) return;
    await call(`/admin-dashboard/host-targets/${id}/cancel`, "POST", { reason });
    tgSearch().catch(() => {});
  }

  // ═══════════════════ سجل المراجعة ═══════════════════
  async function auLoad(page) {
    const q = new URLSearchParams({ page: String(page || 1) });
    if (val("au_action")) q.set("action", val("au_action"));
    if (val("au_user")) q.set("user", val("au_user"));
    if (val("au_from")) q.set("from", val("au_from"));
    if (val("au_to")) q.set("to", new Date(new Date(val("au_to")).getTime() + 86_400_000).toISOString().slice(0, 10));
    const res = await call("/admin-dashboard/audit-log?" + q.toString());
    const d = res?.data || { rows: [], total: 0, page: 1 };
    const j = (v) => (v == null ? "—" : `<code style="white-space:pre-wrap;font-size:11px">${esc(JSON.stringify(v, null, 1)).slice(0, 600)}</code>`);
    document.querySelector("#auTable tbody").innerHTML = d.rows.map((r) => `
      <tr><td>${r.id}</td><td>${dt(r.createdAt)}</td>
        <td>${esc(r.admin?.name || "")}<div class="cell-muted">ID ${esc(r.admin?.displayId ?? r.adminId)}</div></td>
        <td><strong>${esc(r.action)}</strong></td>
        <td>${esc(r.targetType || "")} ${esc(r.targetId || "")}${r.targetUser ? `<div class="cell-muted">${esc(r.targetUser.name || "")} · ID ${esc(r.targetUser.displayId ?? r.targetUser.id)}</div>` : ""}</td>
        <td>${j(r.before)}</td><td>${j(r.after)}</td><td>${esc(r.reason || "—")}</td>
        <td class="cell-muted">${esc(r.ip || "")}<div>${esc((r.userAgent || "").slice(0, 60))}</div></td></tr>`).join("");
    const pages = Math.max(1, Math.ceil(d.total / 50));
    $("auMeta").innerHTML = `${n(d.total)} عملية · صفحة ${d.page} من ${pages} ` +
      (d.page > 1 ? `<button class="btn btn-outline btn-sm" onclick="auLoad(${d.page - 1})">السابق</button>` : "") +
      (d.page < pages ? `<button class="btn btn-outline btn-sm" onclick="auLoad(${d.page + 1})">التالي</button>` : "");
  }

  // ═══════════════════ نوع الغرفة ═══════════════════
  let rmId = null;
  async function rmLoad() {
    const id = intOrEmpty("rm_id");
    if (!id) return;
    const res = await call(`/admin-dashboard/rooms-mgmt/${id}`);
    const r = res?.data;
    rmId = r?.id ?? null;
    $("rmInfo").textContent = r ? `${r.name} · المالك ${r.ownerId} · ${r.isActive ? "مفتوحة" : "مغلقة"} · ${r.isLocked ? "مقفولة بكلمة مرور" : "بدون قفل"}` : "";
    $("rm_type").value = r?.roomType || "USER";
    $("rm_hidden").checked = Boolean(r?.allowHiddenEntry);
  }

  async function rmSave() {
    if (!rmId) return toast("اعرض الغرفة أولاً");
    const reason = reasonFrom("rm_reason");
    if (!reason) return;
    await call(`/admin-dashboard/rooms-mgmt/${rmId}`, "PATCH", {
      roomType: val("rm_type"),
      allowHiddenEntry: $("rm_hidden").checked,
      reason,
    });
    $("rm_reason").value = "";
    toast("✅ تم الحفظ");
    rmLoad().catch(() => {});
  }

  document.addEventListener("input", (e) => {
    if (e.target && (e.target.id === "cpb_program" || e.target.id === "cpb_partner")) cpbTotal();
    if (e.target && (e.target.id === "lk_hostShare" || e.target.id === "lk_rtp")) lkAnalyze();
  });

  Object.assign(window, {
    econLoadGames, econEdit, econSaveGame, econFundGame,
    lkLoad, lkAnalyze, lkSaveSettings, lkSaveTiers, lkFund, lkSearch,
    cpEconLoad, cpbSave, cpcSearch, cpcSave, cplAddRow, cplSave, cplDelete, cpeSave, cpblLoad,
    ftInit, ftSearch, ftGrant, ftRevoke, ftEntries,
    tgSearch, tgSave, tgCancel,
    auLoad,
    rmLoad, rmSave,
  });
})();
