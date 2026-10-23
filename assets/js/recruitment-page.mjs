import {
  stages,
  requestStates,
  routes,
  escapeHTML as esc,
  money,
  dashboard,
  defaultCriteria,
} from "./recruitment-model.mjs?v=1";
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
          hr_review: r.hr_id,
          finance_review: r.finance_id,
          approval: r.approver_id,
        })[r.status] === context.user_id,
    );
    root.innerHTML = `<div class="rec-metrics">${[
      ["شواغر مفتوحة", d.open],
      ["احتياجات تحت الاعتماد", d.pending],
      ["مرشحون في المقابلات", d.interviews],
      ["باشروا العمل", d.hired],
    ]
      .map(
        ([l, v]) =>
          `<article class="rec-metric"><span>${l}</span><strong>${v}</strong></article>`,
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
    root.innerHTML = `<section class="rec-card"><h2>مؤشرات حركة التوظيف</h2><p class="rec-muted">تعكس المؤشرات السجلات المتاحة لك.</p>${rows.map(([l, v]) => `<div class="rec-row"><span>${esc(l)}</span><strong>${v}</strong></div>`).join("")}<div class="rec-actions">${button("طباعة التقرير", "data-print")}</div></section><section class="rec-card"><h2>تجاوزت تاريخ المباشرة المستهدف</h2>${requestRows(overdue)}</section>`;
  }
  if (view === "reference") {
    root.innerHTML = `<section class="rec-card"><h2>مرجع الرواتب والدرجات</h2><p class="rec-muted">نسخة مستوردة من منظومة السلم المعتمدة. الإجمالي يشمل الأساسي والسكن والمواصلات. ربط مسمى مختلف يتطلب توثيق المطابقة من الموارد البشرية.</p><div class="rec-table"><table><thead><tr><th>الوظيفة</th><th>الدرجة</th><th>السعودي</th><th>غير السعودي</th></tr></thead><tbody>${context.salaries.map((s) => `<tr><td>${esc(s.title)}</td><td>${esc(s.grade)}</td><td>${money(s.saudi_min)} – ${money(s.saudi_max)}</td><td>${s.expat_min == null ? "—" : money(s.expat_min) + " – " + money(s.expat_max)}</td></tr>`).join("")}</tbody></table></div></section>`;
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
        "required",
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
          "مسؤول الموارد البشرية",
          people("manage"),
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
          "صاحب الاعتماد النهائي",
          people("approve"),
          "",
          "required",
        ) +
        area(
          "reason",
          "سبب الاحتياج والمبررات",
          "",
          'required maxlength="3000"',
        ) +
        `<label class="wide">المشاركون في المقابلات<select name="interviewer_ids" multiple size="4">${context.people.map((p) => `<option value="${p.id}">${esc(p.full_name)}</option>`).join("")}</select></label><div id="jobPreview" class="rec-note wide"></div><label class="wide">معايير التقييم وأوزانها<textarea name="criteria" required rows="6">${esc(defaultCriteria.map((c) => `${c.key} | ${c.label} | ${c.weight}`).join("\n"))}</textarea><small>كل سطر: الرمز | المعيار | الوزن. مجموع الأوزان 100%. عدّلها لتناسب الوصف قبل إرسال الطلب.</small></label>`,
      "إرسال للمراجعة",
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
    data.criteria = data.criteria
      .split("\n")
      .filter((x) => x.trim())
      .map((line) => {
        const [key, label, weight] = line.split("|").map((x) => x.trim());
        return { key, label, weight: Number(weight) };
      });
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
      ["الموارد البشرية", name(r.hr_id)],
      ["الميزانية", name(r.finance_id)],
      ["الاعتماد", name(r.approver_id)],
      ["الدرجة", r.salary_snapshot?.grade || "تظهر للمخولين"],
      ["مرجع السلم", r.salary_snapshot?.title || "تظهر للمخولين"],
    ]
      .map(([l, v]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
      .join(
        "",
      )}</dl><p class="rec-note">${esc(r.reason)}</p><details><summary>الوصف الوظيفي ومعايير الاختيار</summary><p class="rec-note">${esc(r.job_snapshot.purpose || "")}\n${esc(Object.values(r.job_snapshot.content?.qualifications || {}).join("\n"))}</p>${r.criteria.map((c) => `<p>${esc(c.label)} · ${c.weight}%</p>`).join("")}</details><div class="rec-actions">${ownStage ? button("اعتماد المرحلة", 'data-rec-action="approve"', false) + button("رفض الطلب", 'data-rec-action="reject"') : ""}${r.status === "hr_review" && context.user_id === r.hr_id && context.manage ? button("ربط سلم الرواتب", "data-link-salary") : ""}${context.manage && r.status === "open" && r.route === "advertised" ? button(r.published ? "إيقاف الإعلان" : "تجهيز ونشر الإعلان", `data-rec-action="${r.published ? "unpublish" : "publish"}"`) : ""}${!["closed", "cancelled", "rejected"].includes(r.status) && (context.manage || context.user_id === r.created_by) ? button("إضافة مرشح", "data-add-candidate", false) : ""}${context.manage && !["closed", "cancelled", "rejected"].includes(r.status) ? button("إلغاء الاحتياج", 'data-rec-action="cancel"') : ""}</div>${r.published ? `<p><a href="careers.html?job=${r.public_token}" target="_blank" rel="noopener">فتح صفحة التقديم للشاغر</a></p>` : ""}<section class="rec-card"><h3>المرشحون لهذا الشاغر</h3>${detail.applications.length ? detail.applications.map((a) => `<div class="rec-row"><div><strong>${esc(a.candidate.full_name)}</strong><p>${badge(a.stage, stages)} · ${esc(a.source)}</p></div>${button("ملف المرشح", `data-detail-app="${a.id}"`)}</div>`).join("") : empty("أضف مرشح الإدارة أو انشر الإعلان لاستقبال الطلبات.")}</section><details><summary>سجل الإجراءات والقرارات</summary><div class="rec-history">${detail.events.map((e) => `<p><strong>${esc(eventLabel(e.action))}</strong><br>${esc(e.note)}<br><small>${esc(name(e.actor_id))} · ${esc(date(e.created_at))}</small></p>`).join("")}</div></details>`,
  );
}
const eventLabel = (action) =>
  ({
    request_created: "إنشاء الاحتياج",
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
        : area(
            "note",
            "الملاحظات / مبرر القرار",
            "",
            'required minlength="3" maxlength="3000"',
          ),
      "تأكيد",
    ),
  );
  bindForm(async (data) => {
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
      .map(([l, v]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
      .join(
        "",
      )}</dl><h3>السيرة والخبرة</h3><div class="rec-actions">${button("فتح السيرة الذاتية", `data-resume-open="${a.id}"`)}${context.manage || r.created_by === context.user_id ? button("إرفاق سيرة PDF", `data-resume-add="${a.id}"`) : ""}</div><p class="rec-note">${esc(c.experience)}\n${esc(c.resume_text)}</p><p class="rec-muted">${esc(a.referral_note)}</p><div class="rec-actions">${active && context.manage && { screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage] ? button("نقل إلى " + stages[{ screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage]], `data-stage-app="${a.id}" data-stage="${{ screening: "interview", interview: "assessment", assessment: "recommended" }[a.stage]}"`, false) : ""}${active && ["screening", "interview", "assessment"].includes(a.stage) && (context.manage || r.created_by === context.user_id || r.interviewer_ids.includes(context.user_id)) ? button("جدولة / توثيق مقابلة", `data-interview-app="${a.id}"`) : ""}${active && context.manage && ["recommended", "offer"].includes(a.stage) ? button("إعداد عرض وظيفي", `data-offer-app="${a.id}"`, false) : ""}${active && context.manage && a.stage === "accepted" ? button("تأكيد المباشرة", `data-join-app="${a.id}"`, false) + button("لم يباشر", `data-stage-app="${a.id}" data-stage="no_show"`) : ""}${active && context.manage && !["hired", "rejected", "withdrawn", "no_show"].includes(a.stage) ? button("استبعاد", `data-stage-app="${a.id}" data-stage="rejected"`) + button("انسحاب", `data-stage-app="${a.id}" data-stage="withdrawn"`) : ""}</div><section class="rec-card"><h3>المقابلات والتقييم</h3>${interviews.length ? interviews.map((i) => `<div class="rec-row"><div><strong>${esc(name(i.interviewer_id))}</strong> · ${esc(date(i.scheduled_at))}<p>${esc({ scheduled: "مجدولة", completed: "مكتملة", absent: "لم يحضر" }[i.state])}${i.score != null ? " · " + i.score + " / 100" : ""}</p><p class="rec-muted">${esc(i.notes)}</p>${i.state === "completed" ? `<p>${esc({ suitable: "مناسب", conditional: "مناسب بشروط", unsuitable: "غير مناسب" }[i.recommendation])}</p>` : ""}</div>${i.state === "scheduled" && (context.manage || i.interviewer_id === context.user_id) ? button("تسجيل النتيجة", `data-complete-interview="${i.id}"`) : ""}</div>`).join("") : empty("لا توجد مقابلات مسجلة.")}</section>${detail.can_pay ? `<section class="rec-card"><h3>العروض الوظيفية</h3>${offers.length ? offers.map((o) => `<div class="rec-card"><strong>العرض · النسخة ${o.version}</strong><p>${money(o.total)} شهريًا · ${esc(offerState(o.state))}</p><p>المباشرة المتوقعة: ${esc(o.start_date)} · صالح حتى ${esc(o.expires_on)}</p>${o.exception_reason ? `<p class="rec-note">استثناء عن النطاق: ${esc(o.exception_reason)}</p>` : ""}<div class="rec-actions">${offerButtons(o)}${["approved", "sent", "accepted"].includes(o.state) ? button("عرض / طباعة الخطاب", `data-print-offer="${o.id}"`) : ""}</div></div>`).join("") : empty("لا توجد عروض.")}</section>` : ""}`,
  );
}
const offerState = (s) =>
  ({
    finance_review: "مراجعة مالية",
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
    (o.state === "finance_review" &&
      context.finance &&
      r.finance_id === context.user_id) ||
    (o.state === "approval" &&
      context.approve &&
      r.approver_id === context.user_id)
  )
    actions = [
      ["approve", "اعتماد"],
      ["reject", "رفض"],
    ];
  if (o.state === "approved" && context.manage)
    actions = [["sent", "تسجيل إرسال العرض"]];
  if (o.state === "sent" && context.manage)
    actions = [
      ["accepted", "تسجيل قبول المرشح"],
      ["declined", "تسجيل رفض المرشح"],
      ["expired", "تسجيل انتهاء العرض"],
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
      area("note", "سبب القرار", "", 'required minlength="3" maxlength="3000"'),
      "تأكيد",
    ),
  );
  bindForm(async (data) => {
    await rpc("recruitment_stage", {
      p_application: id,
      p_revision: a.revision,
      p_stage: stage,
      p_note: data.note,
    });
    detail = await rpc("recruitment_detail", { p_request: a.request_id });
    renderApplication(id);
  });
}
function interviewForm(id, existing) {
  const r = detail.request,
    a = detail.applications.find((a) => a.id === id);
  const allowed = context.manage
    ? context.people.filter((p) =>
        [r.hr_id, r.created_by, ...r.interviewer_ids].includes(p.id),
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
            ["hr", "موارد بشرية"],
            ["technical", "فنية"],
            ["previous", "مقابلة سابقة موثقة"],
          ],
          existing?.kind || "hr",
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
        field("expires_on", "صلاحية العرض", "", "date", "required") +
        area("benefits", "المزايا والشروط الإضافية", "", 'maxlength="3000"') +
        area(
          "exception_reason",
          "مبرر الاستثناء إذا تجاوز الإجمالي النطاق",
          "",
          'maxlength="3000"',
        ) +
        `<p class="rec-note wide">الدرجة: ${esc(r.salary_snapshot?.grade)} · المرجع: ${esc(r.salary_snapshot?.title)}<br>النطاق المعتمد: ${money(minimum)} – ${money(maximum)}<br>الإجمالي = الأساسي + السكن + المواصلات. يخضع العرض للمراجعة المالية ثم الاعتماد.</p><p id="offerTotalPreview" class="rec-note wide" role="status"></p>`,
      "حفظ ورفع للاعتماد",
    ),
  );
  const form = $("dialogBody").querySelector("form");
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
        field("existing_employee_id", "معرف سجل موجود للربط عند تطابق البريد") +
        area(
          "note",
          "مرجع محضر المباشرة والمستندات المكتملة",
          "",
          'required minlength="3" maxlength="3000"',
        ) +
        `<label class="rec-check wide"><input type="checkbox" name="documents_complete" required>تم التحقق من اكتمال متطلبات ومستندات التعيين</label><p class="rec-muted wide">ينشأ سجل الموظف دون حساب دخول تلقائي. عند وجود سجل بالبريد نفسه، يلزم التحقق من معرفه للربط دون تعديل بياناته.</p>`,
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
      .map(([l, v]) => `<div><dt>${l}</dt><dd>${esc(v)}</dd></div>`)
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
