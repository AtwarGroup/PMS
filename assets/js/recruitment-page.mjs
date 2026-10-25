import {
  stages,
  requestStates,
  routes,
  escapeHTML as esc,
  money,
  dashboard,
  defaultCriteria,
} from "./recruitment-model.mjs?v=2";
const $ = (id) => document.getElementById(id);
let sb,
  context,
  snapshot,
  detail,
  view = "dashboard",
  busy = false;
const status = (message = "", error = false, dialog = false) => {
  const el = $(dialog ? "dialogStatus" : "pageStatus");
  el.textContent = message;
  el.dataset.error = error;
};
const rpc = async (name, args = {}) => {
  const { data, error } = await sb.rpc(name, args);
  if (error) throw Error(error.message);
  return data;
};
const button = (label, attrs = "", secondary = true) =>
  `<button type="button" class="rec-btn ${secondary ? "secondary" : ""}" ${attrs}>${esc(label)}</button>`;
const field = (name, label, value = "", type = "text", extra = "") =>
  `<label>${esc(label)}<input name="${name}" value="${esc(value)}" type="${type}" ${extra}></label>`;
const area = (name, label, value = "", extra = "") =>
  `<label class="wide">${esc(label)}<textarea name="${name}" ${extra}>${esc(value)}</textarea></label>`;
const select = (name, label, items, value = "", extra = "") =>
  `<label>${esc(label)}<select name="${name}" ${extra}><option value="">اختر…</option>${items.map(([id, text]) => `<option value="${esc(id)}" ${id === value ? "selected" : ""}>${esc(text)}</option>`).join("")}</select></label>`;
const empty = (text) => `<p class="rec-empty">${esc(text)}</p>`;
const badge = (value, labels) =>
  `<span class="rec-tag">${esc(labels[value] || value)}</span>`;
const name = (id) => context.people.find((p) => p.id === id)?.full_name || "—";
const date = (v) =>
  v
    ? new Date(v).toLocaleString("ar-SA", {
        dateStyle: "medium",
        timeStyle: "short",
      })
    : "—";
function show(title, body) {
  $("dialogTitle").textContent = title;
  $("dialogBody").innerHTML = body;
  status("", false, true);
  if (!$("recDialog").open) $("recDialog").showModal();
}
function bindForm(handler) {
  const form = $("dialogBody").querySelector("form");
  form?.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (busy) return;
    busy = true;
    form.querySelectorAll("button").forEach((b) => (b.disabled = true));
    status("جارٍ الحفظ…", false, true);
    try {
      await handler(Object.fromEntries(new FormData(form)), form);
      await refresh();
      status("", false, true);
    } catch (e) {
      status(e.message, true, true);
    } finally {
      busy = false;
      form.querySelectorAll("button").forEach((b) => (b.disabled = false));
    }
  });
}
const formBody = (fields, submit = "حفظ") =>
  `<form class="rec-form"><div class="rec-form-grid">${fields}</div><div class="rec-actions"><button class="rec-btn" type="submit">${esc(submit)}</button></div></form>`;
async function refresh() {
  snapshot = await rpc("recruitment_list");
  render();
}
function requestRows(rows) {
  return rows.length
    ? `<div class="rec-table"><table><thead><tr><th>الطلب والوظيفة</th><th>المسار</th><th>العدد</th><th>المباشرة المستهدفة</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>${rows.map((r) => `<tr><td><strong>REC-${r.number} · ${esc(r.job_snapshot.title)}</strong><br><small>${esc(r.company)} · ${esc(r.location)}</small></td><td>${esc(routes[r.route])}</td><td>${snapshot.applications.filter((a) => a.request_id === r.id && a.stage === "hired").length} / ${r.headcount}</td><td>${esc(r.target_date)}</td><td>${badge(r.status, requestStates)}</td><td>${button("فتح الطلب", `data-request="${r.id}"`)}</td></tr>`).join("")}</tbody></table></div>`
    : empty("لا توجد احتياجات وظيفية في هذا العرض.");
}
function candidateRows(rows) {
  return rows.length
    ? `<div class="rec-table"><table><thead><tr><th>المرشح</th><th>الوظيفة</th><th>المصدر</th><th>المرحلة</th><th>الإجراء</th></tr></thead><tbody>${rows.map((a) => `<tr><td>${esc(a.candidate_name)}</td><td>${esc(a.job_title)}</td><td>${esc(a.source)}</td><td>${badge(a.stage, stages)}</td><td>${button("ملف التقديم", `data-application="${a.id}" data-request-id="${a.request_id}"`)}</td></tr>`).join("")}</tbody></table></div>`
    : empty("لا توجد طلبات تقديم مطابقة.");
}
function render() {
  const root = $("viewContent");
  for (const b of document.querySelectorAll("[data-view]")) {
    if (b.dataset.view === view) b.setAttribute("aria-current", "page");
    else b.removeAttribute("aria-current");
  }
  if (view === "dashboard") {
    const d = dashboard(snapshot.requests, snapshot.applications);
    const mine = snapshot.requests.filter(
      (r) =>
        ({
          department_review: r.department_approver_id,
          hr_exception: r.development_id,
          finance_exception: r.approver_id,
          cancellation_approval: r.approver_id,
          hr_review: r.hr_id,
          finance_review: r.finance_id,
          approval: r.approver_id,
        })[r.status] === context.user_id,
    );
    root.innerHTML = `${taskPanel(snapshot.tasks || [])}<div class="rec-metrics">${[
      ["شواغر مفتوحة", d.open, "blue"],
      ["احتياجات تحت الاعتماد", d.pending, "purple"],
      ["مرشحون في المقابلات", d.interviews, "warning"],
      ["باشروا العمل", d.hired, "success"],
    ]
      .map(
        ([l, v, tone]) =>
          `<article class="rec-metric atwar-metric" data-tone="${tone}"><span>${l}</span><strong>${v}</strong></article>`,
      )
      .join(
        "",
      )}</div><section class="rec-card"><h2>بانتظار إجرائك</h2>${mine.length ? requestRows(mine) : '<p class="rec-muted">لا توجد احتياجات بانتظار اعتمادك.</p>'}${(snapshot.offer_queue || []).map((o) => `<div class="rec-row"><div><strong>${esc(o.candidate_name)}</strong><p>${esc(o.job_title)} · ${esc(offerState(o.state))}</p></div>${button("فتح العرض", `data-application="${o.application_id}" data-request-id="${o.request_id}"`)}</div>`).join("")}</section><section class="rec-card"><h2>آخر الاحتياجات</h2>${requestRows(snapshot.requests.slice(0, 6))}</section>`;
  }
  if (view === "requests") {
    root.innerHTML = `<section class="rec-card"><div class="rec-filter"><input id="filterQuery" type="search" aria-label="البحث عن احتياج" placeholder="ابحث بالمسمى أو رقم الطلب"><select id="filterState" aria-label="حالة الطلب"><option value="">جميع الحالات</option>${Object.entries(
      requestStates,
    )
      .map(([k, l]) => `<option value="${k}">${l}</option>`)
      .join("")}</select></div><div id="filteredRows"></div></section>`;
    const filter = () => {
      $("filteredRows").innerHTML = requestRows(
        snapshot.requests.filter(
          (r) =>
            (!$("filterState").value || r.status === $("filterState").value) &&
            `${r.number} ${r.job_snapshot.title} ${r.company}`.includes(
              $("filterQuery").value.trim(),
            ),
        ),
      );
    };
    $("filterQuery").oninput = filter;
    $("filterState").onchange = filter;
    filter();
  }
  if (view === "candidates") {
    root.innerHTML = `<section class="rec-card"><h2>طلبات المرشحين</h2><p class="rec-muted">ملف واحد للمرشح، وتقييم وقرار مستقل لكل شاغر.</p><div class="rec-filter"><input id="candidateQuery" type="search" aria-label="البحث عن مرشح" placeholder="اسم المرشح أو الوظيفة"><select id="candidateStage" aria-label="مرحلة المرشح"><option value="">جميع المراحل</option>${Object.entries(
      stages,
    )
      .map(([k, l]) => `<option value="${k}">${l}</option>`)
      .join("")}</select></div><div id="candidateRows"></div></section>`;
    const filter = () => {
      $("candidateRows").innerHTML = candidateRows(
        snapshot.applications.filter(
          (a) =>
            (!$("candidateStage").value ||
              a.stage === $("candidateStage").value) &&
            `${a.candidate_name} ${a.job_title}`.includes(
              $("candidateQuery").value.trim(),
            ),
        ),
      );
    };
    $("candidateQuery").oninput = filter;
    $("candidateStage").onchange = filter;
    filter();
  }
  if (view === "interviews") {
    root.innerHTML = `<section class="rec-card"><h2>متابعة المقابلات</h2><p class="rec-muted">افتح ملف المرشح لجدولة المقابلة أو إكمال تقييمها وتوثيق المقابلات السابقة.</p>${(snapshot.interviews || []).length ? `<div class="rec-table"><table><thead><tr><th>الموعد</th><th>المرشح</th><th>المقابل</th><th>الحالة</th><th>الإجراء</th></tr></thead><tbody>${snapshot.interviews.map((i) => `<tr><td>${esc(date(i.scheduled_at))}</td><td>${esc(i.candidate_name)}<br>${esc(i.job_title)}</td><td>${esc(name(i.interviewer_id))}</td><td>${esc({ scheduled: "مجدولة", completed: "مكتملة", absent: "لم يحضر" }[i.state])}</td><td>${button("فتح المقابلة", `data-application="${i.application_id}" data-request-id="${i.request_id}"`)}</td></tr>`).join("")}</tbody></table></div>` : empty("لا توجد مقابلات مسجلة.")}</section>`;
  }
  if (view === "reports") {
    const rows = Object.entries(stages).map(([s, l]) => [
      l,
      snapshot.applications.filter((a) => a.stage === s).length,
    ]);
    const overdue = snapshot.requests.filter(
      (r) =>
        r.target_date < new Date().toISOString().slice(0, 10) &&
        !["closed", "rejected", "cancelled"].includes(r.status),
    );
    root.innerHTML = `<section class="rec-card"><h2>مؤشرات حركة التوظيف</h2><p class="rec-muted">تعكس المؤشرات السجلات المتاحة لك.</p>${rows.map(([l, v, tone]) => `<div class="rec-row"><span>${esc(l)}</span><strong>${v}</strong></div>`).join("")}<div class="rec-actions">${button("طباعة التقرير", "data-print")}</div></section><section class="rec-card"><h2>تجاوزت تاريخ المباشرة المستهدف</h2>${requestRows(overdue)}</section>`;
  }
  if (view === "reference") {
    root.innerHTML = `${calendarPanel()}<section class="rec-card"><h2>مرجع الرواتب والدرجات</h2><p class="rec-muted">نسخة مستوردة من منظومة السلم المعتمدة. الإجمالي يشمل الأساسي والسكن والمواصلات. ربط مسمى مختلف يتطلب توثيق المطابقة من الموارد البشرية.</p><div class="rec-table"><table><thead><tr><th>الوظيفة</th><th>الدرجة</th><th>السعودي</th><th>غير السعودي</th></tr></thead><tbody>${context.salaries.map((s) => `<tr><td>${esc(s.title)}</td><td>${esc(s.grade)}</td><td>${money(s.saudi_min)} – ${money(s.saudi_max)}</td><td>${s.expat_min == null ? "—" : money(s.expat_min) + " – " + money(s.expat_max)}</td></tr>`).join("")}</tbody></table></div></section>`;
  }
}
function createRequest() {
  const people = (kind) =>
    context.people.filter((p) => p[kind]).map((p) => [p.id, p.full_name]);
  show(
    "طلب احتياج وظيفي",
    formBody(
      select(
        "job_id",
        "المسمى والوصف المعتمد",
        context.jobs.map((j) => [j.id, `${j.job_code} · ${j.title}`]),
        "",
        "",
      ) +
        select(
          "department_id",
          "الإدارة",
          context.departments.map((d) => [d.id, d.name]),
          "",
          "required",
        ) +
        select("section_id", "القسم", [], "", "required") +
        select(
          "manager_id",
          "المدير المباشر للموظف الجديد",
          context.managers.map((p) => [p.id, p.full_name]),
        ) +
        field("company", "الشركة", "", "text", 'required maxlength="120"') +
        field(
          "location",
          "الفرع / موقع العمل",
          "",
          "text",
          'required maxlength="120"',
        ) +
        field(
          "headcount",
          "العدد المطلوب",
          1,
          "number",
          'required min="1" max="100"',
        ) +
        field(
          "target_date",
          "تاريخ المباشرة المستهدف",
          "",
          "date",
          "required",
        ) +
        select(
          "route",
          "مسار التوظيف",
          Object.entries(routes),
          "advertised",
          "required",
        ) +
        select(
          "hr_id",
          "أخصائي شؤون الموظفين",
          people("personnel"),
          "",
          "required",
        ) +
        select(
          "finance_id",
          "مراجع الميزانية",
          people("finance"),
          "",
          "required",
        ) +
        select(
          "approver_id",
          "الرئيس التنفيذي",
          people("approve"),
          "",
          "required",
        ) +
        select("department_approver_id", "مدير الإدارة", context.people.map(p=>[p.id,p.full_name]), "", "required") +
        select("supervisor_id", "المدير المباشر / المشرف", context.people.map(p=>[p.id,p.full_name]), "", "required") +
        select("recruiter_id", "مسؤول التوظيف", people("manage"), "", "required") +
        select("development_id", "مشرف تطوير الأعمال", people("development"), "", "required") +
        select("request_type", "نوع الاحتياج", [["new","جديد"],["replacement","إحلال / استبدال"]], "new", "required") +
        field("draft_title", "مسمى المسودة إذا لم يعتمد الوصف بعد") +
        select("linked_request_id", "الطلب السابق عند الإحلال أو إعادة التقديم", snapshot.requests.map(x=>[x.id,`REC-${x.number} · ${x.job_snapshot.title}`])) +
        area(
          "reason",
          "سبب الاحتياج والمبررات",
          "",
          'required maxlength="3000"',
        ) +
        `<label class="wide">المشاركون في المقابلات<select name="interviewer_ids" multiple size="4">${context.people.map((p) => `<option value="${p.id}">${esc(p.full_name)}</option>`).join("")}</select></label><div id="jobPreview" class="rec-note wide"></div><div class="wide"><h3>معايير تقييم المقابلة</h3><p class="rec-muted">المعايير العامة ثابتة، ويحدد المعيار الفني وفق الوصف الوظيفي. مجموع الأوزان ١٠٠٪.</p></div>${defaultCriteria.map((c,i)=>field(`criterion_label_${i}`,i===1?"المعيار الفني المرتبط بالوصف":c.label,c.label,"text",i===1?'required maxlength="250"':'required readonly')+field(`criterion_weight_${i}`,"الوزن ٪",c.weight,"number",'required min="1" max="100"')).join("")}`,
      "حفظ المسودة",
    ),
  );
  const form = $("dialogBody").querySelector("form");
  const updateSections = () => {
    form.elements.section_id.innerHTML =
      '<option value="">اختر…</option>' +
      context.sections
        .filter((s) => s.department_id === form.elements.department_id.value)
        .map((s) => `<option value="${s.id}">${esc(s.name)}</option>`)
        .join("");
  };
  form.elements.department_id.onchange = updateSections;
  form.elements.job_id.onchange = () => {
    const j = context.jobs.find((j) => j.id === form.elements.job_id.value);
    const salary = context.salaries.find(
      (s) => s.title.trim() === j?.title?.trim(),
    );
    $("jobPreview").textContent = j
      ? `${j.snapshot.purpose || ""}\n${Object.values(j.snapshot.content?.qualifications || {}).join("\n")}\n${salary ? "الدرجة: " + salary.grade + " · نطاق السعودي: " + money(salary.saudi_min) + " – " + money(salary.saudi_max) + " · نطاق غير السعودي: " + (salary.expat_min == null ? "غير متاح" : money(salary.expat_min) + " – " + money(salary.expat_max)) : "يُربط السلم تلقائيًا عند تطابق المسمى، وتراجع الموارد البشرية أي مسمى يحتاج مطابقة."}`
      : "";
  };
  bindForm(async (data, form) => {
    data.headcount = Number(data.headcount);
    data.interviewer_ids = new FormData(form).getAll("interviewer_ids");
    data.criteria = defaultCriteria.map((c,i)=>({key:c.key,label:data[`criterion_label_${i}`],weight:Number(data[`criterion_weight_${i}`])}));
    const id = await rpc("recruitment_request_create", { p_data: data });
    await openRequest(id);
  });
}
async function openRequest(id) {
  detail = await rpc("recruitment_detail", { p_request: id });
  renderRequest();
}
function renderRequest() {
  const r = detail.request;
  const ownStage =
    {
      department_review: r.department_approver_id,
          hr_exception: r.development_id,
          finance_exception: r.approver_id,
          cancellation_approval: r.approver_id,
          hr_review: r.hr_id,
      finance_review: r.finance_id,
      approval: r.approver_id,
    }[r.status] === context.user_id;
  show(
    `REC-${r.number} · ${r.job_snapshot.title}`,
    `<div class="rec-actions">${badge(r.status, requestStates)}${badge(r.route, routes)}${button("طباعة الطلب", "data-print")}</div><dl class="rec-detail">${[
      ["الشركة", r.company],
      ["الموقع", r.location],
      ["العدد المطلوب", r.headcount],
      ["تاريخ المباشرة", r.target_date],
      ["مدير الإدارة", name(r.department_approver_id)],
      ["المشرف", name(r.supervisor_id)],
      ["شؤون الموظفين", name(r.hr_id)],
      ["مسؤول التوظيف", name(r.recruiter_id)],
      ["مشرف تطوير الأعمال", name(r.development_id)],
      ["الميزانية", name(r.finance_id)],
      ["الاعتماد", name(r.approver_id)],
      ["الدرجة", r.salary_snapshot?.grade || "تظهر للمخولين"],
      ["مرجع السلم", r.salary_snapshot?.title || "تظهر للمخولين"],
    ]
      .map(([l, v, tone]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
      .join(
        "",
      )}</dl><p class="rec-note">${esc(r.reason)}</p><details><summary>الوصف الوظيفي ومعايير الاختيار</summary><p class="rec-note">${esc(r.job_snapshot.purpose || "")}\n${esc(Object.values(r.job_snapshot.content?.qualifications || {}).join("\n"))}</p>${r.criteria.map((c) => `<p>${esc(c.label)} · ${c.weight}%</p>`).join("")}</details><div class="rec-actions">${ownStage ? button("اعتماد المرحلة", 'data-rec-action="approve"', false) + button("رفض الطلب", 'data-rec-action="reject"') : ""}${["draft", "rejected"].includes(r.status) && [r.created_by,r.recruiter_id,r.hr_id].includes(context.user_id) ? button("ربط سلم الرواتب", "data-link-salary") : ""}${context.manage && r.status === "open" && r.route === "advertised" ? button(r.published ? "إيقاف الإعلان" : "تجهيز ونشر الإعلان", `data-rec-action="${r.published ? "unpublish" : "publish"}"`) : ""}${!["closed", "cancelled", "rejected"].includes(r.status) && (context.manage || context.user_id === r.created_by) ? button("إضافة مرشح", "data-add-candidate", false) : ""}${context.user_id === r.department_approver_id && !["closed", "cancelled", "cancellation_approval"].includes(r.status) ? button("إلغاء الاحتياج", 'data-rec-action="cancel"') : ""}</div>${r.published ? `<p><a href="careers.html?job=${r.public_token}" target="_blank" rel="noopener">فتح صفحة التقديم للشاغر</a></p>` : ""}${requestExtras(r)}<section class="rec-card"><h3>المرشحون لهذا الشاغر</h3>${detail.applications.length ? detail.applications.map((a) => `<div class="rec-row"><div><strong>${esc(a.candidate.full_name)}</strong><p>${badge(a.stage, stages)} · ${esc(a.source)}</p></div>${button("ملف المرشح", `data-detail-app="${a.id}"`)}</div>`).join("") : empty("أضف مرشح الإدارة أو انشر الإعلان لاستقبال الطلبات.")}</section>${context.audit_admin?`<details><summary>سجل الإجراءات والقرارات</summary><div class="rec-history">${detail.events.map((e) => `<p><strong>${esc(eventLabel(e.action))}</strong><br>${esc(e.note)}<br><small>${esc(name(e.actor_id))} · ${esc(date(e.created_at))}</small></p>`).join("")}</div></details>`:''}`,
  );
}
const eventLabel = (action) =>
  ({
    request_created: "إنشاء مسودة احتياج",
    request_submit: "إرسال الاحتياج للموافقات",
    request_edit: "تعديل مسودة الاحتياج",
    request_exception: "طلب استثناء بمبرر",
    request_sourcing_days: "تحديد مدة توفير المرشحين",
    sourcing_suspended: "توقف توفير المرشحين بعد استنفاد الدفعات",
    batch_submit: "تقديم دفعة المرشحين للإدارة",
    batch_none_selected: "عدم اختيار مرشح من الدفعة",
    batch_resume: "اعتماد دفعة إضافية",
    candidate_reused: "ربط ملف مرشح موجود",
    candidate_transferred: "ترشيح المرشح لطلب آخر",
    candidate_previous: "حفظ البيانات السابقة قبل التعديل",
    second_interview: "طلب مقابلة ثانية من مدير الإدارة",
    confirm_join: "تأكيد المدير المباشر للحضور",
    documents_exception: "موافقة مسؤول التوظيف على استكمال المستندات لاحقًا",
    document_review: "مراجعة مستند المرشح",
    update_review: "مراجعة تحديث بيانات المرشح",
    postpone: "تأجيل المباشرة بالتنسيق مع المدير المباشر",
    internal_link: "ربط الترشيح بموظف حالي",
    internal_approve: "موافقة الإدارة الحالية على النقل",
    internal_final: "اعتماد الرئيس التنفيذي للنقل الداخلي",
    transfer: "ترشيح المرشح لوظيفة أخرى",
    offer_returned: "إعادة العرض للتعديل",
    offer_development_review: "رفع استثناء العرض لمشرف تطوير الأعمال",
    offer_hr_review: "مراجعة أخصائي شؤون الموظفين للعرض",
    offer_extended: "تمديد صلاحية العرض بمبرر",
    request_approve: "اعتماد مرحلة",
    request_reject: "رفض الطلب",
    request_link_salary: "ربط مرجع السلم",
    request_publish: "نشر الإعلان",
    request_unpublish: "إيقاف الإعلان",
    request_cancel: "إلغاء الاحتياج",
    candidate_added: "إضافة مرشح",
    public_application: "طلب تقديم خارجي",
    interview_scheduled: "جدولة مقابلة",
    interview_completed: "إكمال تقييم مقابلة",
    interview_absent: "غياب عن المقابلة",
    offer_created: "إعداد عرض",
    offer_finance_review: "مراجعة العرض",
    offer_approval: "رفع العرض للاعتماد",
    offer_approved: "اعتماد العرض",
    offer_sent: "تسجيل إرسال العرض",
    offer_accepted: "قبول العرض",
    offer_declined: "رفض العرض",
    offer_expired: "انتهاء العرض",
    joined: "تأكيد المباشرة",
  })[action] ||
  (action.startsWith("stage_")
    ? "انتقال إلى " + (stages[action.slice(6)] || action)
    : action);
function requestAction(action) {
  const r = detail.request;
  const publish = action === "publish";
  show(
    publish
      ? "تجهيز الإعلان"
      : {
          approve: "اعتماد المرحلة",
          reject: "رفض الطلب",
          cancel: "إلغاء الاحتياج",
          unpublish: "إيقاف الإعلان",
        }[action],
    formBody(
      publish
        ? area(
            "advertisement",
            "الإعلان الوظيفي",
            `${r.job_snapshot.title}\n${r.job_snapshot.purpose || ""}\n${Object.values(r.job_snapshot.content?.qualifications || {}).join("\n")}`,
            'required minlength="20" maxlength="10000"',
          )
        : (action === "approve" && r.status === "hr_review" ? `<label class="rec-check wide"><input type="checkbox" name="request_type_checked" required>تم التحقق من نوع الطلب: ${r.request_type === "replacement" ? "إحلال" : "جديد"}</label><label class="rec-check wide"><input type="checkbox" name="saudization_checked" required>يتوافق الطلب مع خطة التوطين</label><label class="rec-check wide"><input type="checkbox" name="profession_checked" required>تم التحقق من أهلية المهنة وفئة المرشح ومتطلبات التوطين</label>` : "") + area(
            "note",
            "الملاحظات / مبرر القرار",
            "",
            'required minlength="3" maxlength="3000"',
          ),
      "تأكيد",
    ),
  );
  bindForm(async (data) => {
    for (const k of ["request_type_checked","saudization_checked","profession_checked"]) if(data[k]) data[k]=true;
    await rpc("recruitment_request_action", {
      p_id: r.id,
      p_revision: r.revision,
      p_action: action,
      p_data: data,
    });
    await openRequest(r.id);
  });
}
function linkSalary() {
  const r = detail.request;
  const exact = context.salaries.find(
    (s) => s.title.trim() === r.job_snapshot.title.trim(),
  );
  show(
    "ربط السلم المعتمد",
    formBody(
      select(
        "salary_id",
        "المسمى المرجعي والدرجة",
        context.salaries.map((s) => [s.id, `${s.title} · ${s.grade}`]),
        exact?.id || "",
        "required",
      ) +
        area(
          "note",
          "أساس مطابقة المسمى",
          exact ? "تطابق المسمى الوظيفي مع المرجع المعتمد" : "",
          'required minlength="3"',
        ),
      "حفظ الربط",
    ),
  );
  bindForm(async (data) => {
    await rpc("recruitment_request_action", {
      p_id: r.id,
      p_revision: r.revision,
      p_action: "link_salary",
      p_data: data,
    });
    await openRequest(r.id);
  });
}
function addCandidate() {
  const r = detail.request;
  show(
    "إضافة مرشح",
    formBody(
      field("full_name", "اسم المرشح", "", "text", 'required maxlength="150"') +
        field(
          "email",
          "البريد الإلكتروني",
          "",
          "email",
          'required maxlength="200"',
        ) +
        field("phone", "الجوال", "", "tel", 'required maxlength="20"') +
        field("city", "المدينة") +
        field("identity_no", "رقم الهوية / الإقامة") +
        field("passport_no", "رقم الجواز") +
        field("passport_country", "دولة إصدار الجواز") +
        select(
          "saudi",
          "فئة نطاق الراتب",
          [
            ["true", "سعودي"],
            ["false", "غير سعودي"],
          ],
          "",
          "required",
        ) +
        field(
          "source",
          "مصدر المرشح",
          r.route === "referral" ? "ترشيح الإدارة" : "إضافة الموارد البشرية",
          "text",
          "required",
        ) +
        area("experience", "المؤهلات والخبرة", "", 'maxlength="3000"') +
        area(
          "resume_text",
          "ملخص السيرة الذاتية",
          "",
          'required minlength="10" maxlength="10000"',
        ) +
        area(
          "referral_note",
          "سبب الترشيح / ملاحظات الإدارة",
          "",
          'maxlength="3000"',
        ) +
        `<p class="rec-muted wide">إذا أُجريت مقابلة مسبقًا، افتح ملف المرشح وسجلها مع تاريخها وتقييمها بعد فتح الشاغر.</p>`,
    ),
  );
  bindForm(async (data) => {
    data.saudi = data.saudi === "true";
    const id = await rpc("recruitment_candidate_add", {
      p_request: r.id,
      p_data: data,
    });
    detail = await rpc("recruitment_detail", { p_request: r.id });
    renderApplication(id);
  });
}
function renderApplication(id) {
  const a = detail.applications.find((a) => a.id === id),
    c = a.candidate,
    r = detail.request;
  const interviews = detail.interviews.filter((i) => i.application_id === id),
    offers = detail.offers.filter((o) => o.application_id === id);
  const active = r.status === "open";
  show(
    c.full_name,
    `<div class="rec-actions">${button("العودة للشاغر", "data-back-request")}${badge(a.stage, stages)}${button("طباعة الملف", "data-print")}</div><dl class="rec-detail">${[
      ["الوظيفة", r.job_snapshot.title],
      ["الجوال", c.phone],
      ["البريد", c.email],
      ["المدينة", c.city],
      ["الفئة", c.saudi ? "سعودي" : "غير سعودي"],
      ["مصدر الترشيح", a.source],
    ]
      .map(([l, v, tone]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
      .join(
        "",
      )}</dl><h3>السيرة والخبرة</h3><div class="rec-actions">${button("فتح السيرة الذاتية", `data-resume-open="${a.id}"`)}${context.manage || r.created_by === context.user_id ? button("إرفاق سيرة PDF", `data-resume-add="${a.id}"`) : ""}</div><p class="rec-note">${esc(c.experience)}\n${esc(c.resume_text)}</p><p class="rec-muted">${esc(a.referral_note)}</p><div class="rec-actions">${active && (a.stage === "assessment" ? context.user_id === r.department_approver_id : context.user_id === r.recruiter_id) && { screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage] ? button("نقل إلى " + stages[{ screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage]], `data-stage-app="${a.id}" data-stage="${{ screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage]}"`, false) : ""}${active && ["screening", "interview", "assessment"].includes(a.stage) && ([r.recruiter_id,r.supervisor_id,r.department_approver_id].includes(context.user_id)) ? button("جدولة / توثيق مقابلة", `data-interview-app="${a.id}"`) : ""}${active && context.user_id === r.recruiter_id && !a.internal_employee_id && ["recommended", "offer"].includes(a.stage) ? button("إعداد عرض وظيفي", `data-offer-app="${a.id}"`, false) : ""}${active && context.user_id === r.recruiter_id && a.stage === "accepted" && !a.internal_employee_id ? button("مراجعة وتسجيل الموظف", `data-join-app="${a.id}"`, false) + button("لم يباشر", `data-stage-app="${a.id}" data-stage="no_show"`) : ""}${active && !["hired", "rejected", "withdrawn", "no_show"].includes(a.stage) ? (context.user_id === r.department_approver_id ? button("استبعاد مع السبب", `data-stage-app="${a.id}" data-stage="rejected"`) : "") + (context.user_id === r.recruiter_id ? button("انسحاب", `data-stage-app="${a.id}" data-stage="withdrawn"`) : "") : ""}</div>${applicationExtras(a,r)}<section class="rec-card"><h3>المقابلات والتقييم</h3>${interviews.length ? interviews.map((i) => `<div class="rec-row"><div><strong>${esc(name(i.interviewer_id))}</strong> · ${esc(date(i.scheduled_at))}<p>${esc({ scheduled: "مجدولة", completed: "مكتملة", absent: "لم يحضر" }[i.state])}${i.score != null ? " · " + i.score + " / 100" : ""}</p><p class="rec-muted">${esc(i.notes)}</p>${i.state === "completed" ? `<p>${esc({ suitable: "مناسب", conditional: "مناسب بشروط", unsuitable: "غير مناسب" }[i.recommendation])}</p>` : ""}</div>${i.state === "scheduled" && i.interviewer_id === context.user_id ? button("تسجيل النتيجة", `data-complete-interview="${i.id}"`) : ""}</div>`).join("") : empty("لا توجد مقابلات مسجلة.")}</section>${detail.can_pay ? `<section class="rec-card"><h3>العروض الوظيفية</h3>${offers.length ? offers.map((o) => `<div class="rec-card"><strong>العرض · النسخة ${o.version}</strong><p>${money(o.total)} شهريًا · ${esc(offerState(o.state))}</p><dl class="rec-detail"><div><dt>الأساسي</dt><dd>${money(o.basic)}</dd></div><div><dt>السكن</dt><dd>${money(o.housing)}</dd></div><div><dt>المواصلات</dt><dd>${money(o.transport)}</dd></div><div><dt>الدرجة</dt><dd>${esc(o.salary_snapshot.grade)}</dd></div></dl><p class="rec-note">${esc(o.benefits)}</p><p>المباشرة المتوقعة: ${esc(o.start_date)} · صالح حتى ${esc(o.expires_on)}</p>${o.exception_reason ? `<p class="rec-note">استثناء عن النطاق: ${esc(o.exception_reason)}</p>` : ""}<div class="rec-actions">${offerButtons(o)}${["approved", "sent", "accepted"].includes(o.state) ? button("عرض / طباعة الخطاب", `data-print-offer="${o.id}"`) : ""}</div></div>`).join("") : empty("لا توجد عروض.")}</section>` : ""}`,
  );
}
const offerState = (s) =>
  ({
    hr_review: "مراجعة شؤون الموظفين",
    development_review: "مراجعة استثناء مشرف تطوير الأعمال",
    returned: "معاد للتعديل",
    finance_review: "مراجعة شؤون الموظفين",
    approval: "بانتظار الاعتماد",
    approved: "معتمد",
    sent: "تم الإرسال",
    accepted: "مقبول",
    declined: "مرفوض",
    expired: "منتهي",
    superseded: "نسخة سابقة",
  })[s] || s;
function offerButtons(o) {
  const r = detail.request;
  let actions = [];
  if (
    (o.state === "hr_review" && context.personnel && r.hr_id === context.user_id) ||
    (o.state === "development_review" && context.development && r.development_id === context.user_id) ||
    (o.state === "approval" &&
      context.approve &&
      r.approver_id === context.user_id)
  )
    actions = [
      ["approve", "اعتماد"],
      ["reject", "رفض"],
    ];
  if (o.state === "approved" && context.manage && r.recruiter_id === context.user_id)
    actions = [["sent", "تسجيل إرسال العرض"]];
  if (o.state === "sent" && context.manage && r.recruiter_id === context.user_id)
    actions = [
      ["accepted", "تسجيل قبول المرشح"],
      ["declined", "تسجيل رفض المرشح"],
      ["expired", "تسجيل انتهاء العرض"],
      ["extend", "تمديد الصلاحية ٧ أيام بمبرر"],
    ];
  return actions
    .map(([k, l]) =>
      button(l, `data-offer-action="${k}" data-offer-id="${o.id}"`),
    )
    .join("");
}
function stageAction(id, stage) {
  const a = detail.applications.find((a) => a.id === id);
  show(
    "نقل المرشح إلى " + stages[stage],
    formBody(
      (stage === "rejected" ? select("rejection_category","سبب الرفض",[["experience","الخبرة غير مناسبة"],["skills","المهارات غير كافية"],["interview","عدم اجتياز المقابلة"],["availability","عدم التوافق مع متطلبات العمل"],["other","سبب آخر موضح"]],"","required") : "") + area("note", "تفصيل سبب القرار", "", 'required minlength="3" maxlength="3000"'),
      "تأكيد",
    ),
  );
  bindForm(async (data) => {
    await rpc("recruitment_stage", {
      p_application: id,
      p_revision: a.revision,
      p_stage: stage,
      p_note: (data.rejection_category ? ({experience:"الخبرة غير مناسبة",skills:"المهارات غير كافية",interview:"عدم اجتياز المقابلة",availability:"عدم التوافق مع متطلبات العمل",other:"سبب آخر"}[data.rejection_category])+": " : "") + data.note,
    });
    detail = await rpc("recruitment_detail", { p_request: a.request_id });
    renderApplication(id);
  });
}
function interviewForm(id, existing) {
  const r = detail.request,
    a = detail.applications.find((a) => a.id === id);
  const allowed = context.user_id===r.recruiter_id
    ? context.people.filter((p) =>
        [r.supervisor_id, ...(a.second_interview_reason ? [r.department_approver_id] : [])].includes(p.id),
      )
    : context.people.filter((p) => p.id === context.user_id);
  show(
    existing ? "تسجيل نتيجة المقابلة" : "جدولة أو توثيق مقابلة",
    formBody(
      select(
        "interviewer_id",
        "القائم بالمقابلة",
        allowed.map((p) => [p.id, p.full_name]),
        existing?.interviewer_id || context.user_id,
        "required",
      ) +
        select("round", "المقابلة", [["1","الأولى: تقييم المدير المباشر"], ...(a.second_interview_reason ? [["2","الثانية: تقييم مدير الإدارة"]] : [])], String(existing?.round || 1), "required") +
        field(
          "scheduled_at",
          "تاريخ ووقت المقابلة",
          existing?.scheduled_at
            ? new Date(
                new Date(existing.scheduled_at) -
                  new Date().getTimezoneOffset() * 60000,
              )
                .toISOString()
                .slice(0, 16)
            : "",
          "datetime-local",
          "required",
        ) +
        select(
          "kind",
          "نوع المقابلة",
          [

            ["technical", "فنية"],
            ["previous", "مقابلة سابقة موثقة"],
          ],
          existing?.kind || "technical",
          "required",
        ) +
        select(
          "state",
          "الحالة",
          [
            ["scheduled", "مجدولة"],
            ["completed", "مكتملة"],
            ["absent", "لم يحضر"],
          ],
          existing ? "completed" : "scheduled",
          "required",
        ) +
        r.criteria
          .map((c) =>
            select(
              "score_" + c.key,
              `${c.label} (${c.weight}%)`,
              [1, 2, 3, 4, 5].map((x) => [String(x), String(x)]),
            ),
          )
          .join("") +
        select("recommendation", "التوصية", [
          ["suitable", "مناسب"],
          ["conditional", "مناسب بشروط"],
          ["unsuitable", "غير مناسب"],
        ]) +
        area(
          "notes",
          "ملاحظات وأدلة التقييم",
          existing?.notes || "",
          'required minlength="3" maxlength="3000"',
        ),
    ),
  );
  bindForm(async (data) => {
    data.scores = Object.fromEntries(
      r.criteria.map((c) => [c.key, Number(data["score_" + c.key])]),
    );
    if (existing) data.id = existing.id;
    data.scheduled_at = new Date(data.scheduled_at).toISOString();
    await rpc("recruitment_interview_save", {
      p_application: a.id,
      p_data: data,
    });
    detail = await rpc("recruitment_detail", { p_request: r.id });
    renderApplication(id);
  });
}
function offerForm(id) {
  const r = detail.request;
  const candidate = detail.applications.find((a) => a.id === id).candidate;
  const previous=detail.offers.filter(o=>o.application_id===id).sort((a,b)=>b.version-a.version)[0];
  const minimum =
    r.salary_snapshot?.[candidate.saudi ? "saudi_min" : "expat_min"];
  const maximum =
    r.salary_snapshot?.[candidate.saudi ? "saudi_max" : "expat_max"];
  show(
    "إعداد العرض الوظيفي",
    formBody(
      field(
        "basic",
        "الراتب الأساسي",
        "",
        "number",
        'required min="1" step="0.01"',
      ) +
        field(
          "housing",
          "بدل السكن",
          0,
          "number",
          'required min="0" step="0.01"',
        ) +
        field(
          "transport",
          "بدل المواصلات",
          0,
          "number",
          'required min="0" step="0.01"',
        ) +
        field("start_date", "المباشرة المتوقعة", "", "date", "required") +
        `<p class="rec-note wide">صلاحية العرض ٧ أيام من تاريخ الإرسال. يمكن لمسؤول التوظيف تمديدها بمبرر دون تغيير الشروط.</p>` +
        area("benefits", "المزايا والشروط الإضافية", r.salary_snapshot?.benefits?.text || "", 'maxlength="3000"') +
        area("change_reason", "مبرر تعديل العرض", "", previous ? "required minlength=5 maxlength=3000" : "maxlength=3000") +
        area(
          "exception_reason",
          "مبرر الاستثناء إذا تجاوز الإجمالي النطاق",
          "",
          'maxlength="3000"',
        ) +
        `<p class="rec-note wide">الدرجة: ${esc(r.salary_snapshot?.grade)} · المرجع: ${esc(r.salary_snapshot?.title)}<br>النطاق المعتمد: ${money(minimum)} – ${money(maximum)}<br>الإجمالي = الأساسي + السكن + المواصلات. يراجعه أخصائي شؤون الموظفين ثم يعتمده الرئيس التنفيذي. استثناءات الراتب والمزايا تمر بمشرف تطوير الأعمال.</p><p id="offerTotalPreview" class="rec-note wide" role="status"></p>`,
      "حفظ ورفع للاعتماد",
    ),
  );
  const form = $("dialogBody").querySelector("form");
  if(previous)for(const k of ["basic","housing","transport","start_date","benefits"])form.elements[k].value=previous[k];
  const updateTotal = () => {
    const total = ["basic", "housing", "transport"].reduce(
      (n, k) => n + Number(form.elements[k].value || 0),
      0,
    );
    $("offerTotalPreview").textContent =
      "الإجمالي الشهري: " +
      money(total) +
      (minimum != null && maximum != null
        ? total < minimum || total > maximum
          ? " · خارج النطاق ويحتاج مبرر استثناء"
          : " · ضمن النطاق المعتمد"
        : " · لا يوجد نطاق معتمد لهذه الفئة");
  };
  form.addEventListener("input", updateTotal);
  updateTotal();
  bindForm(async (data) => {
    await rpc("recruitment_offer_create", { p_application: id, p_data: data });
    detail = await rpc("recruitment_detail", { p_request: r.id });
    renderApplication(id);
  });
}
function offerAction(id, action) {
  const o = detail.offers.find((o) => o.id === id),
    r = detail.request;
  show(
    "توثيق إجراء العرض",
    formBody(
      area(
        "note",
        action === "sent"
          ? "وسيلة الإرسال وتاريخها"
          : action === "accepted"
            ? "مرجع موافقة المرشح وتاريخها"
            : "الملاحظات وسبب القرار",
        "",
        'required minlength="3" maxlength="3000"',
      ),
      "تأكيد",
    ),
  );
  bindForm(async (data) => {
    await rpc("recruitment_offer_action", {
      p_id: id,
      p_action: action,
      p_note: data.note,
    });
    detail = await rpc("recruitment_detail", { p_request: r.id });
    renderApplication(o.application_id);
  });
}
function joinForm(id) {
  const r = detail.request;
  show(
    "تأكيد المباشرة",
    formBody(
      field(
        "employee_code",
        "الرقم الوظيفي",
        "",
        "text",
        'inputmode="numeric" pattern="[0-9]+"',
      ) +
        field("join_date", "تاريخ المباشرة الفعلي", "", "date", "required") +
        select("existing_employee_id", "سجل الموظف الموجود عند مطابقة البريد", context.managers.map(p=>[p.id,p.full_name])) +
        area(
          "note",
          "مرجع محضر المباشرة والمستندات المكتملة",
          "",
          'required minlength="3" maxlength="3000"',
        ) +
        `<p class="rec-note wide">يُتحقق آليًا من اعتماد المستندات أو وجود استثناء ساري، ومن تأكيد المدير المباشر لتاريخ الحضور.</p><p class="rec-muted wide">ينشأ سجل الموظف دون حساب دخول تلقائي. عند وجود سجل بالبريد نفسه، يلزم اختيار سجله بعد التحقق منه للربط.</p>`,
      "تأكيد وإنشاء سجل الموظف",
    ),
  );
  bindForm(async (data) => {
    data.documents_complete = true;
    await rpc("recruitment_join", { p_application: id, p_data: data });
    detail = await rpc("recruitment_detail", { p_request: r.id });
    renderApplication(id);
  });
}
function printOffer(id) {
  const o = detail.offers.find((o) => o.id === id),
    a = detail.applications.find((a) => a.id === o.application_id),
    r = detail.request;
  show(
    "العرض الوظيفي",
    `<article class="rec-card"><p> ${esc(r.company)}</p><h2>عرض وظيفي</h2><p>السيد / ${esc(a.candidate.full_name)}</p><p>يسرنا تقديم العرض الوظيفي التالي:</p><dl class="rec-detail">${[
      ["المسمى", r.job_snapshot.title],
      ["الدرجة", o.salary_snapshot.grade],
      ["موقع العمل", r.location],
      ["نوع الدوام", "دوام كامل"],
      ["الأساسي", money(o.basic)],
      ["السكن", money(o.housing)],
      ["المواصلات", money(o.transport)],
      ["الإجمالي الشهري", money(o.total)],
      ["تاريخ المباشرة المتوقع", o.start_date],
      ["صلاحية العرض", o.expires_on],
    ]
      .map(([l, v, tone]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
      .join(
        "",
      )}</dl><p class="rec-note">${esc(o.benefits)}</p><p>قبول المرشح: ____________________ التاريخ: ____________________</p><p class="rec-muted">نسخة ${o.version} · ${esc(offerState(o.state))}</p></article><div class="rec-actions">${button("طباعة", "data-print")}${button("العودة للمرشح", `data-detail-app="${a.id}"`)}</div>`,
  );
}
document.addEventListener("click", async (e) => {
  const b = e.target.closest("button");
  if (!b || busy) return;
  try {
    if (b.dataset.view) {
      view = b.dataset.view;
      render();
    } else if (b.dataset.request) await openRequest(b.dataset.request);
    else if (b.dataset.application) {
      detail = await rpc("recruitment_detail", {
        p_request: b.dataset.requestId,
      });
      renderApplication(b.dataset.application);
    } else if (b.hasAttribute("data-back-request")) renderRequest();
    else if (b.dataset.detailApp) renderApplication(b.dataset.detailApp);
    else if (b.dataset.recAction) requestAction(b.dataset.recAction);
    else if (b.hasAttribute("data-link-salary")) linkSalary();
    else if (b.hasAttribute("data-add-candidate")) addCandidate();
    else if (b.dataset.stageApp)
      stageAction(b.dataset.stageApp, b.dataset.stage);
    else if (b.dataset.interviewApp) interviewForm(b.dataset.interviewApp);
    else if (b.dataset.completeInterview) {
      const i = detail.interviews.find(
        (i) => i.id === b.dataset.completeInterview,
      );
      interviewForm(i.application_id, i);
    } else if (b.dataset.offerApp) offerForm(b.dataset.offerApp);
    else if (b.dataset.offerAction)
      offerAction(b.dataset.offerId, b.dataset.offerAction);
    else if (b.dataset.joinApp) joinForm(b.dataset.joinApp);
    else if (b.dataset.resumeOpen) await openResume(b.dataset.resumeOpen);
    else if (b.dataset.resumeAdd) resumeForm(b.dataset.resumeAdd);
    else if (b.dataset.workflow) workflowForm(b.dataset.workflow,b.dataset.app || "");
    else if (b.dataset.documentOpen) await openDocument(b.dataset.documentOpen);
    else if (b.dataset.documentReview) documentReview(b.dataset.documentReview);
    else if (b.dataset.updateReview) updateReview(b.dataset.updateReview);
    else if (b.dataset.printOffer) printOffer(b.dataset.printOffer);
    else if (b.hasAttribute("data-print")) window.print();
  } catch (e) {
    status(e.message, true, $("recDialog").open);
  }
});
$("closeDialog").onclick = () => {
  if (!busy) $("recDialog").close();
};
$("createRequest").onclick = createRequest;
try {
  sb = await window.atwarGetSupabase();
  const session = await window.AtwarSession.require();
  if (session) {
    await window.AtwarModules.guard(sb);
    context = await rpc("recruitment_context");
    $("createRequest").hidden = !context.can_request;
    document.querySelector('[data-view="reference"]').hidden =
      !context.salaries.length;
    await refresh();
    setInterval(() => { if (!busy && !$("recDialog").open) refresh().catch(e=>status(e.message,true)); }, 60000);
    status("");
    const id = new URLSearchParams(location.search).get("request");
    if (id) await openRequest(id);
  }
} catch (e) {
  status("تعذر تحميل التوظيف: " + e.message, true);
}

async function openResume(id) {
  const a = detail.applications.find((a) => a.id === id);
  const { data, error } = await sb.storage
    .from("recruitment-resumes")
    .createSignedUrl(a.resume_token + "/resume.pdf", 120);
  if (error) throw Error("لا يوجد ملف سيرة ذاتية مرفق أو لا تملك صلاحية فتحه.");
  const link = document.createElement("a");
  link.href = data.signedUrl;
  link.target = "_blank";
  link.rel = "noopener";
  link.click();
}
function resumeForm(id) {
  const a = detail.applications.find((a) => a.id === id),
    rid = detail.request.id;
  show(
    "إرفاق السيرة الذاتية",
    formBody(
      '<label>ملف السيرة<input name="resume" type="file" accept="application/pdf" required><small>PDF حتى 5 ميجابايت. يحتفظ النظام بالنسخة الأولى لكل تقديم.</small></label>',
    ),
  );
  bindForm(async (_, form) => {
    const file = new FormData(form).get("resume");
    if (!file?.size || file.size > 5242880 || file.type !== "application/pdf")
      throw Error("اختر ملف PDF لا يزيد عن 5 ميجابايت.");
    const { error } = await sb.storage
      .from("recruitment-resumes")
      .upload(a.resume_token + "/resume.pdf", file, {
        upsert: false,
        contentType: "application/pdf",
      });
    if (error)
      throw Error("تعذر رفع الملف. تحقق من وجود ملف سابق أو أعد المحاولة.");
    detail = await rpc("recruitment_detail", { p_request: rid });
    renderApplication(id);
  });
}

const docLabels = {identity:'الهوية / الإقامة',passport:'الجواز',education:'الشهادة الدراسية',experience:'شهادات الخبرة',license:'الرخصة للسائق أو المندوب',dependents:'هويات المرافقين إن وجدوا',address:'العنوان الوطني',iban:'شهادة الآيبان'};
function taskPanel(tasks){
  const overdue=tasks.filter(t=>new Date(t.due_at)<new Date());
  return `<section class="rec-card"><h2>المهام والمتابعة <span class="rec-tag">${overdue.length} متأخرة</span></h2>${tasks.length ? tasks.map(t=>`<div class="rec-row"><div><strong>${esc(t.label)}</strong><p class="rec-muted">${esc(name(t.owner_id))} · الموعد: ${esc(date(t.due_at))}${new Date(t.due_at)<new Date()?' · متأخر':''}${t.escalated?' · وصل لمسؤول التوظيف للمتابعة':''}</p></div>${button('فتح الطلب',`data-request="${t.request_id}"`)}</div>`).join('') : empty('لا توجد مهام معلقة.')}</section>`;
}
function requestExtras(r){
 const mine=[r.created_by,r.supervisor_id].includes(context.user_id), recruiter=context.user_id===r.recruiter_id;
 const actions=[];
 if(mine&&['draft','rejected'].includes(r.status))actions.push(['submit','إرسال للموافقات'],['edit','تعديل المسودة / إعادة التقديم']);
 if(mine&&r.status==='rejected'&&['hr_review','finance_review'].includes(r.rejected_stage))actions.push(['exception','طلب استثناء بمبرر']);
 if(['closed','cancelled'].includes(r.status)&&context.can_request)actions.push(['copy','طلب جديد مرتبط بهذا الطلب']);
 const b=detail.batches?.at(-1);
 if(r.status==='open'&&r.route==='advertised'&&b){
  if(recruiter&&b.state==='sourcing')actions.push(['batch_submit',`تقديم الدفعة ${b.number} (${b.quota} مرشحين)`]);
  if(recruiter&&b.number===1&&b.state==='sourcing'&&r.sourcing_days===10)actions.push(['sourcing_days','تحديد ١٥ يومًا لوظيفة تخصصية / قيادية']);
  if(context.user_id===r.department_approver_id&&b.state==='review')actions.push(['batch_none','لم يتم اختيار أحد من الدفعة']);
  if(context.user_id===r.development_id&&b.number>=3&&b.state==='exhausted')actions.push(['batch_resume','اعتماد استئناف توفير المرشحين']);
 }
 return `<section class="rec-card"><h3>دورة الطلب</h3><p class="rec-muted">المشرف ← مدير الإدارة ← شؤون الموظفين والتوطين ← المدير المالي ← الرئيس التنفيذي ← مسؤول التوظيف</p><div class="rec-actions">${actions.map(([k,l])=>button(l,`data-workflow="${k}"`)).join('')}</div>${b?`<p>الدفعة الحالية: ${b.number} · العدد ${b.quota} · ${esc({sourcing:'توفير المرشحين',review:'تقييم الإدارة',exhausted:b.number>=3?'توفير المرشحين متوقف؛ الطلب مفتوح':'مستنفدة',selected:'تم الاختيار'}[b.state])}</p>`:''}${r.versions?.length?`<details><summary>نسخ الطلب السابقة (${r.versions.length})</summary>${r.versions.map(v=>`<p>النسخة ${v.revision} · ${esc(v.job_snapshot?.title)} · العدد ${v.headcount} · ${esc(v.reason)}</p>`).join('')}</details>`:''}</section>${taskPanel(detail.tasks||[])}`;
}
function applicationExtras(a,r){
 const active=r.status==='open', recruiter=context.user_id===r.recruiter_id, manager=context.user_id===r.department_approver_id;
 const actions=[];
 if(active&&manager&&['screening','interview','assessment'].includes(a.stage)&&!a.second_interview_reason)actions.push(['second_interview','طلب مقابلة ثانية']);
 if(active&&context.user_id===r.supervisor_id&&a.stage==='accepted')actions.push(['confirm_join','تأكيد الحضور الفعلي']);
 if(recruiter&&(active||(a.stage==='hired'&&a.documents_exception_due))){actions.push(['portal_link','رابط المرشح لتحديث البيانات والمستندات'],['document_prepare','إرفاق مستند']);if(active)actions.push(['transfer','ترشيح لطلب آخر']);if(a.stage==='accepted')actions.push(['documents_exception','استثناء نقص مستندات'],['postpone','تأجيل المباشرة بالتنسيق']);if(a.stage==='screening'&&!a.internal_employee_id)actions.push(['internal_link','ربط ترشيح داخلي بموظف حالي']);}
 if(active&&a.internal_employee_id){if(context.user_id===a.internal_manager_id&&!a.internal_approved)actions.push(['internal_approve','موافقة الإدارة الحالية على النقل']);if(a.internal_approved&&a.selection_approved&&context.user_id===r.approver_id&&a.stage==='recommended')actions.push(['internal_final','اعتماد النقل الداخلي وتنفيذه']);}
 const docs=(detail.documents||[]).filter(d=>d.application_id===a.id);
 const updates=(detail.updates||[]).filter(u=>u.application_id===a.id&&u.state==='pending');
 const history=(detail.updates||[]).filter(u=>u.application_id===a.id&&u.state==='approved'&&u.previous_data);
 const previous=(detail.previous_interviews||[]).filter(i=>i.candidate_id===a.candidate_id);
 return `<section class="rec-card"><h3>التعيين والمستندات</h3><div class="rec-actions">${actions.map(([k,l])=>button(l,`data-workflow="${k}" data-app="${a.id}"`)).join('')}</div>${a.second_interview_reason?`<p>سبب المقابلة الثانية: ${esc(a.second_interview_reason)}</p>`:''}${a.joining_confirmed_on?`<p>أكد المدير المباشر الحضور بتاريخ ${esc(a.joining_confirmed_on)}</p>`:''}${a.documents_exception_due?`<p class="rec-note">مستندات ناقصة تحت المتابعة حتى ${esc(a.documents_exception_due)} · ${esc(a.documents_exception_reason)}</p>`:''}${a.internal_employee_id?`<p>ترشيح داخلي · موافقة الإدارة الحالية: ${a.internal_approved?'تمت':'بانتظارها'} · لا ينشأ طلب إحلال تلقائي.</p>`:''}<p class="rec-muted">المطلوب: الهوية، الجواز، الشهادة، الخبرات، العنوان الوطني، شهادة الآيبان. الرخصة للسائق أو المندوب، وهويات المرافقين عند توفرهم.</p>${docs.map(d=>`<div class="rec-row"><div>${esc(docLabels[d.kind])} · ${esc({pending:'قيد المراجعة',approved:'معتمد',rejected:'معاد للاستكمال'}[d.state])}<p class="rec-muted">${esc(date(d.created_at))} · ${esc(d.note)}</p></div><div class="rec-actions">${button('فتح',`data-document-open="${d.id}"`)}${recruiter?button('مراجعة',`data-document-review="${d.id}"`):''}</div></div>`).join('')}${updates.length?`<h4>تغييرات المرشح بانتظار الاعتماد</h4>${updates.map(u=>`<div class="rec-card"><p>${esc(u.data.phone)} · ${esc(u.data.city)}</p><p class="rec-note">${esc(u.data.experience)}\n${esc(u.data.resume_text)}</p>${recruiter?button('مراجعة التغييرات',`data-update-review="${u.id}"`):''}</div>`).join('')}`:''}${history.length?`<details><summary>سجل بيانات المرشح السابقة</summary>${history.map(u=>`<p>${esc(date(u.created_at))}</p><p class="rec-note">${esc(u.previous_data.phone)} · ${esc(u.previous_data.city)}\n${esc(u.previous_data.experience)}\n${esc(u.previous_data.resume_text)}</p>`).join('')}</details>`:''}${previous.length?`<details><summary>التقييمات السابقة للمرشح</summary>${previous.map(i=>`<p>${esc(name(i.interviewer_id))} · ${esc(date(i.scheduled_at))} · ${i.score??'—'} / 100</p><p class="rec-note">${esc(i.notes)}</p>`).join('')}</details>`:''}</section>`;
}
function workflowForm(action,app){
 const r=detail.request,a=detail.applications.find(x=>x.id===app);let fields='',title='توثيق الإجراء';
 const notes=()=>area('note','المبرر / مرجع القرار','','required minlength="5" maxlength="3000"');
 if(action==='copy'){
  createRequest();const form=$('dialogBody').querySelector('form');for(const k of ['job_id','company','location','headcount','route','hr_id','finance_id','approver_id','department_approver_id','supervisor_id','recruiter_id','development_id','reason','department_id'])if(form.elements[k])form.elements[k].value=r[k]||'';form.elements.department_id.onchange();form.elements.section_id.value=r.section_id;form.elements.linked_request_id.value=r.id;form.elements.request_type.value=r.status==='closed'?'replacement':r.request_type;return;
 }
 if(action==='submit'){title='إرسال طلب الاحتياج للموافقات';fields=notes();}
 if(action==='edit'){title='تعديل الطلب وحفظ نسخته السابقة';fields=select('job_id','الوصف المعتمد',context.jobs.map(j=>[j.id,j.title]),r.job_id)+field('headcount','العدد',r.headcount,'number','required min="1" max="100"')+field('target_date','المباشرة المستهدفة',r.target_date,'date','required')+area('reason','سبب الاحتياج',r.reason,'required')+notes();}
 if(['exception','sourcing_days','batch_none','second_interview','internal_approve'].includes(action))fields=notes();
 if(action==='batch_submit')fields=`<label class="wide">المرشحون الجدد للدفعة<select name="application_ids" multiple size="8" required>${detail.applications.filter(a=>!a.batch_number&&!['hired','rejected','withdrawn','no_show'].includes(a.stage)).map(a=>`<option value="${a.id}">${esc(a.candidate.full_name)}</option>`).join('')}</select></label>`+notes();
 if(action==='batch_resume')fields=field('quota','عدد المرشحين الإضافيين المعتمد','','number','required min="1" max="100"')+notes();
 if(['confirm_join','internal_final'].includes(action))fields=field('join_date','تاريخ الحضور / النقل الفعلي','','date','required')+notes();
 if(action==='documents_exception')fields=field('due_date','موعد استكمال النواقص','','date','required')+notes();
 if(action==='postpone')fields=field('start_date','المباشرة الجديدة','','date','required')+`<label class="rec-check wide"><input type="checkbox" name="coordinated" required>تم التنسيق مع المدير المباشر</label>`+notes();
 if(action==='portal_link')fields='<p class="rec-note wide">رابط خاص صالح ٧ أيام؛ يتيح تقديم تغييرات ومستندات للمراجعة. شاركه مع المرشح من وسيلة التواصل المناسبة.</p>';
 if(action==='document_prepare')fields=select('kind','نوع المستند',Object.entries(docLabels),'','required')+'<label>ملف PDF<input name="file" type="file" accept="application/pdf" required><small>حتى ٥ ميجابايت؛ تحفظ كل نسخة مستقلة.</small></label>';
 if(action==='transfer')fields=select('target_request','طلب التوظيف المستهدف',snapshot.requests.filter(x=>x.id!==r.id&&x.status==='open').map(x=>[x.id,`REC-${x.number} · ${x.job_snapshot.title}`]),'','required')+`<label class="rec-check wide"><input type="checkbox" name="consent" required>وافق المرشح على الترشيح للوظيفة وتم التحقق من الملاءمة</label>`+notes();
 if(action==='internal_link')fields=select('employee_id','الموظف الحالي',context.managers.map(p=>[p.id,p.full_name]),'','required')+select('current_manager_id','مدير الإدارة الحالية',context.people.map(p=>[p.id,p.full_name]),'','required')+notes();
 show(title,formBody(fields,'تأكيد وحفظ'));
 bindForm(async(data,form)=>{
  for(const k of ['consent','coordinated'])if(data[k])data[k]=true;
  let result;
  if(action.startsWith('batch_')){if(action==='batch_submit')data.application_ids=new FormData(form).getAll('application_ids');await rpc('recruitment_batch_action',{p_request:r.id,p_action:{batch_submit:'submit',batch_none:'none_selected',batch_resume:'resume'}[action],p_data:data});}
  else if(['submit','edit','exception','sourcing_days'].includes(action))await rpc('recruitment_request_action',{p_id:r.id,p_revision:r.revision,p_action:action,p_data:data});
  else{result=await rpc('recruitment_application_action',{p_application:app,p_action:action,p_data:data});if(action==='document_prepare')await uploadDocument(result.file_token,new FormData(form).get('file'));}
  if(action==='portal_link'){
   const url=new URL('candidate.html',location.href);url.searchParams.set('token',result.token);
   show('رابط تحديث بيانات المرشح',`<p class="rec-note">هذا الرابط خاص بالمرشح وصالح ٧ أيام.</p>${field('portal_url','الرابط الخاص',url.href,'url','readonly')}<div class="rec-actions">${button('العودة للمرشح',`data-detail-app="${app}"`)}</div>`);return;
  }
  detail=await rpc('recruitment_detail',{p_request:r.id});app?renderApplication(app):renderRequest();
 });
}
async function uploadDocument(token,file){
 if(!file?.size||file.size>5242880||file.type!=='application/pdf')throw Error('اختر ملف PDF حتى ٥ ميجابايت.');
 const {error}=await sb.storage.from('recruitment-documents').upload(`${token}/document.pdf`,file,{upsert:false,contentType:'application/pdf'});if(error)throw Error(error.message);
}
async function openDocument(id){const d=detail.documents.find(d=>d.id===id);const {data,error}=await sb.storage.from('recruitment-documents').createSignedUrl(`${d.file_token}/document.pdf`,120);if(error)throw Error('الملف لم يرفع أو ليس متاحًا.');const link=document.createElement('a');link.href=data.signedUrl;link.target='_blank';link.rel='noopener';link.click();}
function documentReview(id){const d=detail.documents.find(x=>x.id===id);reviewRecord('document_review',d.application_id,'document_id',id);}
function updateReview(id){const u=detail.updates.find(x=>x.id===id);reviewRecord('update_review',u.application_id,'update_id',id);}
function reviewRecord(action,app,key,id){const rid=detail.request.id;show('مراجعة واعتماد',formBody(select('state','القرار',[['approved','اعتماد'],['rejected','إعادة للاستكمال']],'','required')+area('note','ملاحظات المراجعة','','required minlength="3"')));bindForm(async data=>{data[key]=id;await rpc('recruitment_application_action',{p_application:app,p_action:action,p_data:data});detail=await rpc('recruitment_detail',{p_request:rid});renderApplication(app);});}
function calendarPanel(){if(!context.development)return '';return `<section class="rec-card"><h2>تقويم أيام العمل</h2><p class="rec-muted">الجمعة والسبت واليوم الوطني ويوم التأسيس مستثناة تلقائيًا. أضف تواريخ الإجازات الرسمية الأخرى المعتمدة.</p><div class="rec-actions">${button('إضافة إجازة رسمية','data-calendar="add"')}</div>${(context.holidays||[]).map(h=>`<div class="rec-row"><span>${esc(h.day)} · ${esc(h.label)}</span>${button('إزالة',`data-calendar="remove" data-day="${h.day}"`)}</div>`).join('')}</section>`;}
document.addEventListener('click',e=>{const b=e.target.closest('[data-calendar]');if(!b||busy)return;const action=b.dataset.calendar;show('تقويم العمل',formBody(field('day','التاريخ',b.dataset.day||'','date','required')+field('label','اسم الإجازة','','text',action==='add'?'required':'')));bindForm(async data=>{await rpc('recruitment_calendar',{p_action:action,p_data:data});context=await rpc('recruitment_context');$('recDialog').close();});});
