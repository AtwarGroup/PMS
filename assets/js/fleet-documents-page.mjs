import { escapeHTML as esc } from "./access-model.mjs";
export const documentKinds = {
  authorization: "تفويض السائق",
  registration: "رخصة السير",
  insurance: "التأمين",
  inspection: "الفحص الدوري",
};
export async function initFleetDocuments({ rpc, show, run }) {
  let data;
  const $ = (id) => document.getElementById(id);
  async function load() {
    data = await rpc("fleet_documents_context");
    render();
  }
  function render() {
    $("documentSettings").hidden = !data.can_configure;
    const vehicleFilter = new URLSearchParams(location.search).get("vehicle");
    $("documentRows").innerHTML = data.vehicles
      .filter((v) => !vehicleFilter || v.id === vehicleFilter)
      .map(
        (v) =>
          `<tr><td><b>${esc(v.plate)}</b><small>${esc(v.driver_name || "غير مسندة")}</small></td>${Object.entries(
            documentKinds,
          )
            .map(([kind]) => {
              const d = data.documents.find(
                (d) => d.vehicle_id === v.id && d.kind === kind,
              );
              return `<td>${d ? `<b>${esc(d.expires_on)}</b><small class="${d.days_left < 0 ? "fleet-expired" : ""}">${d.days_left < 0 ? "منتهية منذ " + Math.abs(d.days_left) + " يوم" : d.days_left === 0 ? "تنتهي اليوم" : "متبقي " + d.days_left + " يوم"}</small>${d.days_left >= 0 && d.days_left <= d.days_before ? "<small>ضمن مدة التنبيه</small>" : ""}` : '<span class="fleet-muted">غير مسجل</span>'}</td>`;
            })
            .join(
              "",
            )}<td>${data.can_edit ? `<button type="button" class="fleet-btn secondary" data-documents="${esc(v.id)}">تحديث الوثائق</button>` : ""}</td></tr>`,
      )
      .join("");
    $("documentEmpty").hidden = data.vehicles.length > 0;
    $("documentRules").textContent = data.settings
      .map((s) => `${documentKinds[s.kind]}: قبل ${s.days_before} يوم`)
      .join(" · ");
  }
  function editor(vehicleId) {
    const v = data.vehicles.find((v) => v.id === vehicleId);
    show(
      `وثائق السيارة ${v.plate}`,
      "تصل التنبيهات إلى مسؤول الأسطول والسائق ومديره المباشر.",
      `<div class="fleet-form">${Object.entries(documentKinds)
        .map(([kind, label]) => {
          const d = data.documents.find(
            (d) => d.vehicle_id === vehicleId && d.kind === kind,
          );
          return `<form class="fleet-card fleet-wide" data-document-kind="${kind}"><h3>${label}</h3><div class="fleet-form"><label>تاريخ الانتهاء<input name="expires" type="date" value="${esc(d?.expires_on || "")}" min="2000-01-01" max="2200-12-31" required></label><label>سبب التحديث<input name="reason" required minlength="3" maxlength="500"></label><div><button class="fleet-btn" type="submit">حفظ التاريخ</button></div></div></form>`;
        })
        .join("")}</div>`,
    );
    for (const form of $("dialogBody").querySelectorAll("[data-document-kind]"))
      form.onsubmit = (e) =>
        run(e, async () => {
          const kind = form.dataset.documentKind,
            d = data.documents.find(
              (d) => d.vehicle_id === vehicleId && d.kind === kind,
            );
          await rpc("fleet_document_save", {
            p_vehicle: vehicleId,
            p_kind: kind,
            p_expires: form.elements.expires.value,
            p_revision: d?.revision ?? null,
            p_reason: form.elements.reason.value,
          });
          await load();
          editor(vehicleId);
          $("dialogStatus").textContent =
            "تم تحديث الوثيقة والتحقق من التنبيهات المستحقة.";
        });
  }
  $("documentRows").onclick = (e) => {
    const b = e.target.closest("[data-documents]");
    if (b) editor(b.dataset.documents);
  };
  $("refreshDocuments").onclick = () =>
    load().catch((e) => {
      $("fleetStatus").textContent = e.message;
    });
  $("documentSettings").onclick = () => {
    show(
      "إعدادات تنبيهات الوثائق",
      "حدد عدد الأيام قبل الانتهاء لكل نوع. هذه الإعدادات لمسؤول النظام فقط.",
      `<div class="fleet-form">${data.settings.map((s) => `<form class="fleet-card" data-setting-kind="${s.kind}"><label>${documentKinds[s.kind]} — أيام قبل الانتهاء<input name="days" type="number" min="0" max="3650" step="1" value="${s.days_before}" required></label><button class="fleet-btn" type="submit">حفظ مدة التنبيه</button></form>`).join("")}</div>`,
    );
    for (const form of $("dialogBody").querySelectorAll("[data-setting-kind]"))
      form.onsubmit = (e) =>
        run(e, async () => {
          const s = data.settings.find(
            (s) => s.kind === form.dataset.settingKind,
          );
          await rpc("fleet_alert_setting_save", {
            p_kind: s.kind,
            p_days: Number(form.elements.days.value),
            p_revision: s.revision,
          });
          await load();
          $("dialogStatus").textContent =
            "تم حفظ مدة التنبيه وتطبيقها على الوثائق.";
        });
  };
  await load();
  if (new URLSearchParams(location.search).get("view") === "documents")
    document.querySelector("[data-tab=documents]").click();
}
