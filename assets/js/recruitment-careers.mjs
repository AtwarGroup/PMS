import { escapeHTML as esc } from "./recruitment-model.mjs?v=1";
const sb = await window.atwarGetSupabase(),
  root = document.getElementById("publicJobs"),
  status = document.getElementById("publicStatus");
const token = new URLSearchParams(location.search).get("job");
const field = (name, label, type = "text", extra = "") =>
  `<label>${label}<input name="${name}" type="${type}" required ${extra}></label>`;
const area = (name, label, extra = "") =>
  `<label class="wide">${label}<textarea name="${name}" required ${extra}></textarea></label>`;
try {
  const { data, error } = await sb.rpc("recruitment_public_jobs", {
    p_token: token,
  });
  if (error) throw error;
  status.textContent = "";
  root.innerHTML = data.length
    ? data
        .map(
          (j) =>
            `<article class="rec-card"><p class="recruitment-eyebrow">${esc(j.company)} · ${esc(j.location)}</p><h2>${esc(j.title)}</h2><p class="rec-note">${esc(j.advertisement)}</p><details><summary class="rec-btn">التقديم على الوظيفة</summary><form class="rec-form" data-token="${j.token}"><div class="rec-form-grid">${field("full_name", "الاسم الكامل", "text", 'maxlength="150" minlength="2" autocomplete="name"')}${field("email", "البريد الإلكتروني", "email", 'maxlength="200" autocomplete="email"')}${field("phone", "الجوال", "tel", 'maxlength="20" autocomplete="tel"')}${field("city", "المدينة", "text", 'maxlength="100"')}<label>فئة التقديم<select name="saudi" required><option value="">اختر…</option><option value="true">سعودي</option><option value="false">غير سعودي</option></select></label>${area("experience", "المؤهلات والخبرات", 'maxlength="3000"')}${area("resume_text", "ملخص مهني عن خبرتك ومدى ملاءمتها للوظيفة", 'minlength="30" maxlength="10000"')}<label class="wide">السيرة الذاتية (اختياري)<input name="resume" type="file" accept="application/pdf"><small>PDF بحد أقصى 5 ميجابايت.</small></label><label class="rec-check wide"><input name="consent" type="checkbox" required>أوافق على استخدام بياناتي وسيرتي الذاتية لدراسة طلب التوظيف والتواصل معي بشأنه.</label></div><button type="submit" class="rec-btn">إرسال الطلب</button><p class="rec-muted" role="status" aria-live="polite"></p></form></details></article>`,
        )
        .join("")
    : '<p class="rec-empty">لا توجد فرص متاحة للتقديم حاليًا.</p>';
  for (const form of root.querySelectorAll("form"))
    form.onsubmit = async (e) => {
      e.preventDefault();
      const submit = form.querySelector("button[type=submit]"),
        feedback = form.querySelector("[role=status]");
      submit.disabled = true;
      feedback.textContent = "جارٍ إرسال الطلب…";
      try {
        const fd = new FormData(form),
          file = fd.get("resume");
        if (
          file?.size > 5242880 ||
          (file?.size && file.type !== "application/pdf")
        )
          throw Error("يرجى إرفاق ملف PDF لا يزيد عن 5 ميجابايت.");
        const payload = Object.fromEntries(fd);
        delete payload.resume;
        payload.saudi = payload.saudi === "true";
        payload.consent = true;
        const { data: receipt, error } = await sb.rpc(
          "recruitment_public_apply",
          { p_token: form.dataset.token, p_data: payload },
        );
        if (error) throw error;
        let uploaded = true;
        if (file?.size) {
          const { error } = await sb.storage
            .from("recruitment-resumes")
            .upload(`${receipt}/resume.pdf`, file, {
              upsert: false,
              contentType: "application/pdf",
            });
          uploaded = !error;
        }
        form.innerHTML = `<p class="rec-note">تم استلام طلب التقديم. ستراجع الموارد البشرية الطلبات وتتواصل مع المرشحين المناسبين.${uploaded ? "" : " تم حفظ بيانات الطلب، وتعذر إرفاق السيرة الذاتية؛ يمكنك تزويد الموارد البشرية بها عند التواصل."}</p>`;
      } catch (e) {
        feedback.textContent = "تعذر الإرسال: " + e.message;
        submit.disabled = false;
      }
    };
} catch (e) {
  status.textContent = "تعذر تحميل الفرص الوظيفية. يرجى المحاولة لاحقًا.";
}
