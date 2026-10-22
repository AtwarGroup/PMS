import {initFleetOperations} from "./fleet-operations.mjs?v=2";
import { initFleetDocuments } from "./fleet-documents-page.mjs?v=3";
import {
  englishDigits,
  dashboardRequests,
  states,
  types,
  actions,
  money,
  quoteTotal,
  requestActions,
  filterRequests,
  summary,
  settlement,
  escapeHTML,
} from "./fleet-model.mjs?v=3";
const esc = value => escapeHTML(englishDigits(value));
const $ = (id) => document.getElementById(id),
  sb = await window.atwarGetSupabase();
let operations,
  context,
  currentDetail,
  currentEdit,
  busy = false,
  initialView = true;
const status = (text, error = false, dialog = false) => {
  const e = $(dialog ? "dialogStatus" : "fleetStatus");
  e.textContent = text;
  e.dataset.error = String(error);
};
async function rpc(name, args = {}) {
  const { data, error } = await sb.rpc(name, args);
  if (error) throw Error(error.message);
  return data;
}
const opt = (id, label, selected) =>
  `<option value="${esc(id)}" ${String(id) === String(selected) ? "selected" : ""}>${esc(label)}</option>`;
const field = (name, label, value = "", type = "text", extra = "") =>
  `<label>${esc(label)}<input lang="${type === "number" ? "en" : "ar"}" name="${name}" type="${type}" value="${esc(value)}" ${extra}></label>`;
const amountField = (name, label, value = "") =>
  field(
    name,
    label,
    value,
    "number",
    'required min="0" max="99999999" step="0.01"',
  );
const fileField = (name, label, required = false) =>
  `<label>${esc(label)}<input name="${name}" type="file" accept="application/pdf,image/png,image/jpeg" ${required ? "required" : ""}><small class="fleet-muted">PDF أو صورة · حتى 5 ميجابايت</small></label>`;
const badge = (s) =>
  `<span class="fleet-tag ${esc(s)}">${esc(states[s] || s)}</span>`;
const button = (text, attrs = "", secondary = false) =>
  `<button type="button" class="fleet-btn ${secondary ? "secondary" : ""}" ${attrs}>${esc(text)}</button>`;
function show(title, subtitle, body) {
  $("dialogTitle").textContent = title;
  $("dialogSubtitle").textContent = subtitle;
  $("dialogBody").innerHTML = body;
  status("", false, true);
  if (!$("fleetDialog").open) $("fleetDialog").showModal();
}
function switchTab(id) {
  if(document.querySelector(`[data-tab="${id}"]`)?.hidden)return;
  for (const b of document.querySelectorAll("[data-tab]")) {
    const active = b.dataset.tab === id;
    b.setAttribute("aria-selected", active);
    b.tabIndex = active ? 0 : -1;
    $(b.dataset.tab).hidden = !active;
  }
}
async function load() {
  context = await rpc("fleet_snapshot");
  render();
  if(operations)await operations.refresh();
  if(initialView && context.finance_only && !context.can_view_vehicles)switchTab("requests");
  initialView=false;
  status("");
}
function render() {
  $('newRequest').hidden=!context.can_create;
  for(const [tab,allowed] of [['vehicles',context.can_view_vehicles],['documents',context.can_view_documents]]){
    const button=document.querySelector(`[data-tab="${tab}"]`);
    button.hidden=!allowed;
    if(!allowed)$(tab).hidden=true;
  }
  if(document.querySelector('[data-tab][aria-selected="true"]')?.hidden)switchTab('requests');

  const scope = $('dashboardScope');
  const scopes = [...(context.vehicles.some(v=>v.driver_id===context.employee_id)?[['personal','متابعتي الشخصية']]:[]),...((context.team_employee_ids||[]).length?[['team','متابعة فريقي']]:[]),...(context.can_oversee?[['all','المتابعة العامة']]:[])];
  const selected = scopes.some(([key])=>key===scope.value)?scope.value:scopes[0]?.[0]||'all';
  scope.innerHTML=scopes.map(([key,label])=>opt(key,label,selected)).join('');
  scope.closest('label').hidden=scopes.length<2;
  const dashboardRows=dashboardRequests(context,selected);
  const m = summary(dashboardRows);
  $("openCount").textContent = m.open;
  $("outstanding").textContent = money(m.outstanding);
  $("totalCost").textContent = money(m.cost);
  $("closedCount").textContent = m.closed;
  $("newRequest").disabled = !context.vehicles.some(
    (v) => v.active && v.can_request,
  );
  $("newVehicle").hidden = !context.can_manage;
  $("importVehicles").hidden = !context.can_manage;
  const queue = dashboardRows.filter((r) =>
    requestActions(r, context).some(
      (a) => !["edit", "request_increase"].includes(a),
    ),
  );
  $("myQueue").innerHTML =
    queue
      .slice(0, 12)
      .map(
        (r) =>
          `<div class="fleet-queue"><div><b>طلب #${esc(r.number)} · ${esc(r.driver_name)}</b><p>${esc(r.description)}</p>${badge(r.state)}</div>${button("فتح الطلب", `data-request="${esc(r.id)}"`, true)}</div>`,
      )
      .join("") || '<p class="fleet-muted">لا توجد طلبات بانتظار إجرائك.</p>';
  $("stageSummary").innerHTML =
    Object.entries(states)
      .filter(([key]) => dashboardRows.some((r) => r.state === key))
      .map(([key, label]) => {
        const n = dashboardRows.filter((r) => r.state === key).length;
        return `<div class="fleet-stage"><span>${esc(label)}</span><b>${n}</b><progress max="${Math.max(1, dashboardRows.length)}" value="${n}" aria-label="${esc(label)}"></progress></div>`;
      })
      .join("") || '<p class="fleet-muted">ستظهر مراحل العمل مع أول طلب.</p>';
  $("vehicleRows").innerHTML = context.vehicles
    .map(
      (v) =>
        `<tr><td><b>${esc(v.plate)}</b><small>${esc(v.vin || "—")}</small></td><td>${esc(v.vehicle_type)}<small>${esc(v.model)}</small></td><td>${esc(v.driver_name || "غير مسندة")}</td><td>${esc(v.city || "—")}</td><td>${Number(v.odometer).toLocaleString("ar-SA-u-nu-latn")} كم</td><td>${v.active ? "نشطة" : "موقوفة"}<small>${esc({available:"متاحة",maintenance:"تحت الصيانة",stopped:"متوقفة"}[v.operational_status]||"متاحة")}</small></td><td>${button("ملف السيارة", `data-history="${esc(v.id)}"`, true)} ${context.can_manage ? button("تعديل", `data-vehicle="${esc(v.id)}"`, true) : ""}</td></tr>`,
    )
    .join("");
  $("vehicleEmpty").hidden = context.vehicles.length > 0;
  renderRequests();
  operations?.render();
}
function renderRequests() {
  if (!context) return;
  const rows = filterRequests(context.requests, {
    query: $("requestSearch").value,
    state: $("stateFilter").value,
  });
  $("requestRows").innerHTML = rows
    .map(
      (r) =>
        `<tr><td><b>#${esc(r.number)}</b><small>${new Date(r.created_at).toLocaleDateString("ar-SA-u-nu-latn")}</small></td><td>${esc(r.driver_name)}<small>${esc(r.plate)}</small></td><td>${esc(r.description)}</td><td>${badge(r.state)}</td><td>${money(r.approved)} ر.س</td><td>${button("عرض الطلب", `data-request="${esc(r.id)}"`, true)}</td></tr>`,
    )
    .join("");
  $("requestEmpty").hidden = rows.length > 0;
}
function vehicleEditor(id) {
  const v = context.vehicles.find((v) => v.id === id) || {};
  show(
    id ? "تعديل بيانات السيارة" : "إضافة سيارة",
    "الربط من سجل الموظفين الحالي",
    `<form id="vehicleForm" class="fleet-form">${field("plate", "رقم اللوحة", v.plate, "text", 'required maxlength="30"')}${field("vin", "رقم الهيكل", v.vin, "text", 'maxlength="40"')}${field("vehicle_type", "نوع السيارة", v.vehicle_type, "text", 'required maxlength="100"')}${field("model", "الموديل", v.model, "text", 'maxlength="100"')}${field("city", "المدينة", v.city, "text", 'maxlength="100"')}${field("odometer", "قراءة العداد (كم)", v.odometer || 0, "number", 'required min="0" step="1"')}${v.id?`<input type="hidden" name="driver_id" value="${esc(v.driver_id||'')}">`:""}<label>السائق<select name="driver_id" disabled>${opt("", "غير مسندة", v.driver_id)}${context.employees.map((e) => opt(e.id, `${e.name} — ${e.code}`, v.driver_id)).join("")}</select><small class="fleet-muted">تُضاف السيارة دون سائق؛ الإسناد وتغيير العهدة يتمان بمحضر التسليم والاستلام.</small></label><label>التشغيل<select name="active">${opt("true", "نشطة", String(v.active ?? true))}${opt("false", "موقوفة", String(v.active ?? true))}</select></label>${field("reason", "سبب الإضافة أو التعديل", "", "text", 'required minlength="3" maxlength="500"')}<div class="fleet-wide"><button class="fleet-btn" type="submit">حفظ السيارة</button></div></form>`,
  );
  $("vehicleForm").onsubmit = (e) =>
    run(e, async () => {
      const data = Object.fromEntries(new FormData(e.target));
      const reason = data.reason;
      delete data.reason;
      await rpc("fleet_vehicle_save", {
        p_id: v.id || null,
        p_revision: v.revision || null,
        p_data: data,
        p_reason: reason,
      });
      await load();
      $("fleetDialog").close();
      status("تم حفظ السيارة وتوثيق التغيير.");
    });
}
function quoteEditor(q = {}, i) {
  return `<section class="fleet-quote fleet-wide" data-quote><header><b>عرض ${i + 1}</b>${button("إزالة", "data-remove-quote", true)}</header><div class="fleet-form">${field("supplier", "المورد / الورشة", q.supplier, "text", 'required minlength="2" maxlength="200"')}<label>المرفق ${q.file_id ? '<small class="fleet-muted">يوجد مرفق محفوظ؛ ارفع ملفًا لاستبداله.</small>' : ""}<input name="file" type="file" accept="application/pdf,image/jpeg,image/png" ${q.file_id ? "" : "required"}></label><div class="fleet-quote-grid fleet-wide">${amountField("parts", "قطع الغيار", q.parts || 0)}${amountField("labor", "أجرة اليد", q.labor || 0)}${amountField("tax", "الضريبة", q.tax || 0)}</div></div><p>الإجمالي: <b data-quote-total>${money(quoteTotal(q))}</b> ر.س</p><input type="hidden" name="file_id" value="${esc(q.file_id || "")}"></section>`;
}
async function requestEditor(id) {
  let r = {};
  if (id) r = (await rpc("fleet_detail", { p_id: id })).request;
  currentEdit = r;
  const vehicles = context.vehicles.filter(
      (v) => v.can_request && v.active,
    ),
    v = vehicles.find((v) => v.id === r.vehicle_id) || vehicles[0];
  show(
    id ? `تعديل الطلب #${r.number}` : "طلب صيانة جديد",
    `${context.can_operate ? "اختر سيارة الموظف المعني؛ يمكنك تقديم الطلب لأي موظف." : "اختر سيارتك أو سيارة أحد موظفيك المباشرين؛ يبقى الطلب باسم صاحب السيارة."}`,
    `<form id="requestForm" class="fleet-form"><label>السيارة<select name="vehicle_id" ${vehicles.length === 1 ? 'aria-label="سيارتك المسجلة"' : ""}>${vehicles.map((v) => opt(v.id, `${v.driver_name || "غير مسندة"} — ${v.plate} — ${v.vehicle_type} ${v.model}`, r.vehicle_id || vehicles[0]?.id)).join("")}</select></label><label>المحاسب المسؤول<select name="accountant_id" required><option value="">اختر المحاسب</option>${context.accountants
      .filter((a) => a.id !== context.user_id)
      .map((a) => opt(a.id, a.name, r.accountant_id))
      .join(
        "",
      )}</select></label><label>نوع الطلب<select name="request_type">${Object.entries(
      types,
    )
      .map(([key, label]) => opt(key, label, r.request_type || "repair"))
      .join(
        "",
      )}</select></label>${field("odometer", "قراءة العداد الحالية (كم)", r.odometer ?? v?.odometer ?? 0, "number", `required min="${v?.odometer || 0}" step="1"`)}<label class="fleet-wide">تفاصيل الصيانة المطلوبة<textarea name="description" required minlength="3" maxlength="4000">${esc(r.description)}</textarea></label><label class="fleet-wide">سبب العطل والملاحظات<textarea name="fault_notes" maxlength="4000">${esc(r.fault_notes)}</textarea></label><div class="fleet-wide"><h3>عروض الأسعار</h3><p class="fleet-muted">ثلاثة عروض من موردين مختلفين. عند إرفاق أقل من ثلاثة، يتطلب الطلب استثناءً مسببًا من مسؤول الأسطول.</p></div><div id="quotesHost" class="fleet-form fleet-wide">${(r.quotes?.length ? r.quotes : [{}, {}, {}]).map(quoteEditor).join("")}</div><div class="fleet-wide">${button("إضافة عرض", 'id="addQuote"', true)}</div><label>العرض المختار<select name="selected_quote" id="selectedQuote"></select></label><div class="fleet-wide fleet-finance">حتى 300 ر.س: اعتماد المدير ثم الإصلاح من عهدة السائق والاستعاضة بعد مراجعة الأسطول.<br>أكثر من 300 ر.س: اعتماد الأسطول ثم الصرف والإصلاح والتسوية.</div><div class="fleet-wide fleet-form-actions"><button type="submit" class="fleet-btn">حفظ المسودة والمرفقات</button></div></form>`,
  );
  const refresh = () => {
    const select = $("selectedQuote"),
      old = select.value;
    select.innerHTML = [...document.querySelectorAll("[data-quote]")]
      .map((q, i) => opt(i, `عرض ${i + 1}`, old || r.selected_quote || 0))
      .join("");
  };
  refresh();
  $("addQuote").onclick = () => {
    const n = $("quotesHost").children.length;
    if (n >= 10) return;
    $("quotesHost").insertAdjacentHTML("beforeend", quoteEditor({}, n));
    refresh();
  };
  $("quotesHost").onclick = (e) => {
    if (e.target.closest("[data-remove-quote]")) {
      e.target.closest("[data-quote]").remove();
      refresh();
    }
  };
  $("quotesHost").oninput = (e) => {
    const q = e.target.closest("[data-quote]");
    if (q) {
      const values = Object.fromEntries(
        [...q.querySelectorAll("input")].map((x) => [x.name, x.value]),
      );
      q.querySelector("[data-quote-total]").textContent = money(
        quoteTotal(values),
      );
    }
  };
  $("requestForm").elements.vehicle_id.onchange = (e) => {
    const v = vehicles.find((v) => v.id === e.target.value),
      o = $("requestForm").elements.odometer;
    o.min = v.odometer;
    o.value = v.odometer;
  };
  $("requestForm").onsubmit = (e) =>
    run(e, async () => {
      const form = e.target,
        data = Object.fromEntries(new FormData(form)),
        quotes = [...document.querySelectorAll("[data-quote]")].map((q) =>
          Object.fromEntries(
            [...q.querySelectorAll("input:not([type=file])")].map((x) => [
              x.name,
              x.value,
            ]),
          ),
        );
      data.quotes = quotes;
      const saved = await rpc("fleet_request_save", {
        p_id: currentEdit.id || null,
        p_revision: currentEdit.revision || null,
        p_data: data,
      });
      // Retain the saved ID immediately: an upload retry must never create a duplicate request.
      currentEdit = (await rpc("fleet_detail", { p_id: saved })).request;
      for (const [i, q] of [
        ...document.querySelectorAll("[data-quote]"),
      ].entries()) {
        const file = q.querySelector("input[type=file]").files[0];
        if (file) {
          const fileId = await upload(saved, "quote", file);
          quotes[i].file_id = fileId;
          q.querySelector("[name=file_id]").value = fileId;
          q.querySelector("input[type=file]").value = "";
          q.querySelector("input[type=file]").required = false;
        }
      }
      const latest = (await rpc("fleet_detail", { p_id: saved })).request;
      await rpc("fleet_request_save", {
        p_id: saved,
        p_revision: latest.revision,
        p_data: { ...data, quotes },
      });
      await load();
      $("fleetDialog").close();
      status("تم حفظ المسودة. افتحها من طلبات الصيانة لإرسالها للاعتماد.");
    });
}
async function upload(id, kind, file) {
  if (
    file.size > 5242880 ||
    !["application/pdf", "image/png", "image/jpeg"].includes(file.type)
  )
    throw Error("اختر PDF أو PNG أو JPEG بحد أقصى 5 ميجابايت.");
  const base64 = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
  return rpc("fleet_upload", {
    p_request: id,
    p_kind: kind,
    p_name: file.name,
    p_mime: file.type,
    p_base64: base64,
  });
}
async function openRequest(id) {
  currentDetail = await rpc("fleet_detail", { p_id: id });
  const r = currentDetail.request,
    meta = context.requests.find((x) => x.id === id) || r,
    allowed = requestActions(r, context),
    balance = settlement(r);
  show(
    `طلب صيانة #${r.number}`,
    `${meta.driver_name || ""} · ${meta.plate || ""}`,
    `<section>${operations?.journeyHTML(r,currentDetail.journey)||""}${badge(r.state)}<h3>${esc(r.description)}</h3><p>${esc(r.fault_notes)}</p><div class="fleet-form"><p>نوع الطلب: <b>${esc(types[r.request_type])}</b></p><p>العداد: <b>${esc(r.odometer)} كم</b></p><p>المحاسب: <b>${esc(meta.accountant_name || "—")}</b></p><p>مسار الطلب: <b>${r.route === "small" ? "حتى 300 ريال — استعاضة" : r.route === "large" ? "أكثر من 300 ريال — صرف مسبق" : "يُحدد عند الإرسال"}</b></p></div><div class="fleet-finance">المعتمد: <b>${money(r.approved)} ر.س</b> · المصروف: <b>${money(r.advance)} ر.س</b> · الفاتورة: <b>${r.invoice_total ? money(r.invoice_total) + " ر.س" : "لم تُرفع"}</b>${r.proposed_total ? `<p>الإجمالي المطلوب بعد الزيادة: ${money(r.proposed_total)} ر.س — ${esc(r.increase_reason)}</p>` : ""}${r.invoice_total ? `<p>${esc(balance.label)}: ${money(balance.amount)} ر.س</p>` : ""}</div>${r.exception_reason ? `<p>سبب استثناء العروض: ${esc(r.exception_reason)}</p>` : ""}<h3>عروض الأسعار</h3><div class="fleet-table-wrap"><table><thead><tr><th>المورد</th><th>قطع الغيار</th><th>أجرة اليد</th><th>الضريبة</th><th>الإجمالي</th></tr></thead><tbody>${r.quotes.map((q, i) => `<tr><td>${esc(q.supplier)}${i === r.selected_quote ? " · المختار" : ""}</td><td>${money(q.parts)}</td><td>${money(q.labor)}</td><td>${money(q.tax)}</td><td>${money(quoteTotal(q))}</td></tr>`).join("")}</tbody></table></div><h3>المرفقات</h3>${currentDetail.files.map((f) => `<div class="fleet-file">${button(f.name, `data-download="${esc(f.id)}"`, true)}<small>${esc({ quote: "عرض سعر", invoice: "فاتورة", payment: "إثبات صرف", refund: "إثبات استرداد" }[f.kind])}</small></div>`).join("") || '<p class="fleet-muted">لا توجد مرفقات.</p>'}<div class="fleet-action-buttons">${allowed.map((a) => button(a === "edit" ? "تعديل المسودة" : actions[a], `data-action="${a}"`, ["return", "reject", "decline_increase"].includes(a))).join("")}</div><div id="actionHost"></div><h3>سجل الإجراءات</h3><ol class="fleet-history">${currentDetail.events.map((e) => `<li><b>${esc(actions[e.action] || { draft_saved: "حفظ المسودة" }[e.action] || e.action)}</b> · ${esc(e.actor_name)}<small>${new Date(e.created_at).toLocaleString("ar-SA-u-nu-latn")} ${e.to_state ? " · " + esc(states[e.to_state]) : ""}</small>${e.payload.reason ? `<p>${esc(e.payload.reason)}</p>` : ""}</li>`).join("")}</ol>${currentDetail.payments.length ? `<h3>الحركات المالية</h3>${currentDetail.payments.map((p) => `<p>${esc({ advance: "صرف عهدة", refund: "استرداد متبقٍ", reimbursement: "استعاضة", topup: "صرف فرق", settle: "تسوية" }[p.kind])}: ${money(p.amount)} ر.س · المرجع ${esc(p.reference)}</p>`).join("")}` : ""}</section>`,
  );
}
function actionEditor(action) {
  const r = currentDetail.request;
  if (action === "edit") {
    requestEditor(r.id).catch((e) => status(e.message, true, true));
    return;
  }
  let fields = "";
  if (
    [
      "approve_exception",
      "return",
      "reject",
      "decline_increase",
      "request_increase",
    ].includes(action)
  )
    fields += field(
      "reason",
      "السبب",
      "",
      "text",
      'required minlength="3" maxlength="1000"',
    );
  if (action === "request_increase")
    fields += amountField("total", "الإجمالي المطلوب بعد الزيادة");
  if (action === "confirm_repair")
    fields +=
      amountField("total", "إجمالي الفاتورة") +
      fileField("invoice", "الفاتورة", true) +
      `<label class="fleet-wide"><span><input name="received" type="checkbox" required style="width:auto"> أؤكد اكتمال الإصلاح واستلام السيارة</span></label><p class="fleet-muted fleet-wide">إذا شملت الفاتورة ضريبة، تحقق من اسم المؤسسة ورقمها الضريبي. الزيادة تحتاج اعتمادًا مسبقًا قبل تنفيذها.</p>`;
  if (["confirm_advance", "settle"].includes(action)) {
    const diff =
      action === "confirm_advance"
        ? {
            amount: Number(r.approved) - Number(r.advance),
            kind: "payment",
            label: "صرف للسائق",
          }
        : settlement(r);
    fields +=
      `<div class="fleet-finance fleet-wide">${esc(diff.label)}: <b>${money(diff.amount)} ر.س</b></div>` +
      field(
        "reference",
        "مرجع العملية / التسوية",
        "",
        "text",
        'required minlength="3" maxlength="200"',
      ) +
      (diff.amount
        ? fileField(
            "evidence",
            diff.kind === "refund" ? "إثبات استرداد المتبقي" : "إثبات الصرف",
            true,
          )
        : "");
  }
  if (!fields) fields = '<p class="fleet-wide">هل تؤكد تنفيذ هذا الإجراء؟</p>';
  $("actionHost").innerHTML =
    `<section class="fleet-card" style="margin-top:20px"><h3>${esc(actions[action])}</h3><form id="actionForm" class="fleet-form">${fields}<div class="fleet-wide"><button type="submit" class="fleet-btn">تأكيد الإجراء</button></div></form></section>`;
  $("actionForm").scrollIntoView({ block: "nearest" });
  $("actionForm").onsubmit = (e) =>
    run(e, async () => {
      const data = Object.fromEntries(new FormData(e.target));
      if (action === "confirm_repair") {
        data.invoice_id = await upload(
          r.id,
          "invoice",
          e.target.elements.invoice.files[0],
        );
        data.received = true;
        delete data.invoice;
      }
      if (["confirm_advance", "settle"].includes(action)) {
        const diff =
          action === "confirm_advance"
            ? {
                amount: Number(r.approved) - Number(r.advance),
                kind: "payment",
              }
            : settlement(r);
        data.amount = diff.amount;
        if (diff.amount)
          data.evidence_id = await upload(
            r.id,
            diff.kind,
            e.target.elements.evidence.files[0],
          );
        delete data.evidence;
      }
      await rpc("fleet_command", {
        p_id: r.id,
        p_revision: r.revision,
        p_action: action,
        p_data: data,
      });
      await load();
      $("fleetDialog").close();
      status("تم تنفيذ الإجراء وتوثيقه.");
    });
}
async function run(event, work) {
  event?.preventDefault();
  if (busy) return;
  busy = true;
  const buttons = [...$("fleetDialog").querySelectorAll("button")];
  buttons.forEach((b) => (b.disabled = true));
  status("جارٍ الحفظ…", false, true);
  try {
    await work();
  } catch (e) {
    status(e.message, true, true);
  } finally {
    busy = false;
    buttons.forEach((b) => (b.disabled = false));
  }
}
$("dialogBody").onclick = async (e) => {
  if (busy) return;
  const a = e.target.closest("[data-action]"),
    d = e.target.closest("[data-download]");
  if (a) actionEditor(a.dataset.action);
  if (d)
    try {
      const f = await rpc("fleet_download", { p_id: d.dataset.download });
      const bytes = Uint8Array.from(atob(f.base64.replace(/\s/g, "")), (c) =>
          c.charCodeAt(0),
        ),
        url = URL.createObjectURL(new Blob([bytes], { type: f.mime })),
        link = document.createElement("a");
      link.href = url;
      link.download = f.name;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
      status(error.message, true, true);
    }
};
document.querySelector("main").addEventListener("click", async (e) => {
  const r = e.target.closest("[data-request]"),
    v = e.target.closest("[data-vehicle]"),
    h = e.target.closest("[data-history]");
  try {
    if (r) await openRequest(r.dataset.request);
    if (v) vehicleEditor(v.dataset.vehicle);
    if (h) await operations.vehicleProfile(h.dataset.history);
  } catch (error) {
    status(error.message, true);
  }
});
$("dashboardScope").onchange = () => render();
$("newVehicle").onclick = () => vehicleEditor();
$("newRequest").onclick = () =>
  requestEditor().catch((e) => status(e.message, true));
$("closeDialog").onclick = () => {
  if (!busy) $("fleetDialog").close();
};
$("fleetDialog").addEventListener("cancel", (e) => {
  if (busy) e.preventDefault();
});
for (const b of document.querySelectorAll("[data-tab]")) {
  b.onclick = () => switchTab(b.dataset.tab);
  b.onkeydown = (e) => {
    if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) {
      e.preventDefault();
      const tabs = [...document.querySelectorAll("[data-tab]")].filter(tab=>!tab.hidden);
      const i =
        e.key === "Home"
          ? 0
          : e.key === "End"
            ? tabs.length - 1
            : (tabs.indexOf(b) +
                (e.key === "ArrowLeft" ? 1 : -1) +
                tabs.length) %
              tabs.length;
      switchTab(tabs[i].dataset.tab);
      tabs[i].focus();
    }
  };
}
$("stateFilter").innerHTML =
  opt("", "جميع المراحل", "") +
  Object.entries(states)
    .map(([id, name]) => opt(id, name, ""))
    .join("");
$("requestSearch").oninput = renderRequests;
$("stateFilter").onchange = renderRequests;
operations=initFleetOperations({rpc,show,run,getContext:()=>context,reload:load,openRequest,switchTab});
try {
  const {
    data: { session },
    error,
  } = await sb.auth.getSession();
  if (error) throw error;
  if (!session?.user) location.replace("../login.html");
  else {
    await load();
    if(context.can_view_documents)await initFleetDocuments({ rpc, show, run });
    const target=new URLSearchParams(location.search);
    if(target.get("request"))await openRequest(target.get("request"));
    if(target.get("handover")){switchTab("handovers");await operations.openHandover(target.get("handover"));}
  }
} catch (e) {
  status(e.message, true);
}

$("importVehicles").onclick = () => {
  show(
    "استيراد سجل السيارات",
    "معاينة دون حفظ، ثم تأكيد الاستيراد بعد مراجعة النتيجة.",
    `<form id="importForm" class="fleet-form"><label class="fleet-wide">ملف الاستيراد المُجهز<input name="source" type="file" accept="application/json,.json" required><small class="fleet-muted">يُجهز من ملف السيارات ويطابق السائقين بسجل الموظفين الحالي. السيارات المباعة تُسجل موقوفة.</small></label><div class="fleet-wide"><button type="submit" class="fleet-btn">فحص ومعاينة الاستيراد</button></div></form><div id="importResult"></div>`,
  );
  $("importForm").onsubmit = (e) =>
    run(e, async () => {
      const file = e.target.elements.source.files[0];
      if (file.size > 2097152)
        throw Error("ملف الاستيراد أكبر من الحد المسموح.");
      const source = JSON.parse(await file.text());
      if (!Array.isArray(source.rows) || !source.source_sha256)
        throw Error("ملف استيراد غير صالح.");
      const result = await rpc("fleet_import", {
        p_rows: source.rows,
        p_source_hash: source.source_sha256,
        p_dry_run: true,
      });
      $("importResult").innerHTML =
        `<div class="fleet-finance">المعاينة: ${result.added} سيارة جديدة · ${result.updated} سجلًا للتحديث.<br>لم يُحفظ أي تغيير.</div>${source.issues?.length ? `<p>ملاحظات تحتاج مراجعة: ${source.issues.length}. السائق غير المطابق سيظل غير مسند.</p><ul>${source.issues.map((i) => `<li>${esc(i.driver_name || i.vin)} — ${esc(i.issue)}</li>`).join("")}</ul>` : ""}<button id="confirmImport" class="fleet-btn">تأكيد استيراد السجلات</button>`;
      status("اكتملت المعاينة دون حفظ.", false, true);
      $("confirmImport").onclick = (event) =>
        run(event, async () => {
          await rpc("fleet_import", {
            p_rows: source.rows,
            p_source_hash: source.source_sha256,
            p_dry_run: false,
          });
          await load();
          $("fleetDialog").close();
          status("تم استيراد سجل السيارات وتوثيق العملية.");
        });
    });
};
