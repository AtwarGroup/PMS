import { escapeHTML } from "./access-model.mjs";
import { englishDigits } from "./fleet-model.mjs?v=3";
import {documentKinds, documentStates, documentState, documentDateError, filterDocumentVehicles} from './fleet-document-model.mjs?v=20261102.1';
const esc = value => escapeHTML(englishDigits(value));
export {documentKinds};
export async function initFleetDocuments({ rpc, show, run }) {
  let data;
  let firstLoad = true;
  const $ = (id) => document.getElementById(id);
  async function load() {
    data = await rpc("fleet_documents_context");
    populateFilters();
    render();
  }
  const options = (items, selected) => items.map(([value, label]) => `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${esc(label)}</option>`).join('');
  function populateFilters() {
    const selectedVehicle = firstLoad ? new URLSearchParams(location.search).get('vehicle') || '' : $('documentVehicle').value;
    const vehicles = [['', 'جميع السيارات'], ...data.vehicles.map(v => [v.id, v.plate])];
    if (selectedVehicle && !vehicles.some(([id]) => id === selectedVehicle)) vehicles.push([selectedVehicle, 'سيارة غير متاحة']);
    $('documentVehicle').innerHTML = options(vehicles, selectedVehicle);
    const drivers = [...new Set(data.vehicles.map(v => v.driver_name || '__unassigned__'))].sort((a,b) => a.localeCompare(b,'ar'));
    $('documentDriver').innerHTML = options([['','جميع السائقين'], ...drivers.map(name => [name, name === '__unassigned__' ? 'دون سائق' : name])], $('documentDriver').value);
    if (firstLoad) {
      $('documentKind').innerHTML = options([['','جميع الأنواع'], ...Object.entries(documentKinds)], '');
      $('documentState').innerHTML = options([['','جميع الحالات'], ...Object.entries(documentStates)], '');
    }
    firstLoad = false;
  }
  function render() {
    if (!data) return;
    $('documentSettings').hidden = !data.can_configure;
    const filters = {vehicle: $('documentVehicle').value, driver: $('documentDriver').value, kind: $('documentKind').value, state: $('documentState').value, query: $('documentSearch').value, from: $('documentDateFrom').value, to: $('documentDateTo').value};
    const error = documentDateError(filters);
    $('documentDateTo').setCustomValidity(error);
    $('documentFilterStatus').textContent = error;
    const rows = filterDocumentVehicles(data, filters);
    for (const header of document.querySelectorAll('#documents th[data-document-kind]')) header.hidden = Boolean(filters.kind && header.dataset.documentKind !== filters.kind);
    $('documentRows').innerHTML = rows.map(({vehicle: v, documents, state}) =>
      `<tr class="fleet-document-row fleet-document-${state}" data-document-state="${state}" data-document-vehicle="${esc(v.id)}"><td><b>${esc(v.plate)}</b><small>${esc(v.driver_name || 'غير مسندة')}</small><small class="fleet-document-status">${esc(documentStates[state])}</small></td>${Object.keys(documentKinds).map(kind => {
        const d = documents.get(kind), state = documentState(d);
        return `<td class="fleet-document-cell-${state}" data-kind="${kind}" ${filters.kind && kind !== filters.kind ? 'hidden' : ''}>${d ? `<b>${esc(d.expires_on)}</b><small>${d.days_left < 0 ? 'منتهية منذ ' + Math.abs(d.days_left) + ' يوم' : d.days_left === 0 ? 'تنتهي اليوم' : 'متبقي ' + d.days_left + ' يوم'}</small>${d.days_left >= 0 && d.days_left <= d.days_before ? '<small>ضمن مدة التنبيه</small>' : ''}` : '<span class="fleet-muted">غير مسجل</span>'}</td>`;
      }).join('')}<td>${data.can_edit ? `<button type="button" class="fleet-btn secondary" data-documents="${esc(v.id)}">تحديث الوثائق</button>` : ''}</td></tr>`
    ).join('');
    $('documentResultCount').textContent = `عرض ${rows.length} من ${data.vehicles.length} سيارة`;
    $('documentEmpty').hidden = rows.length > 0;
    $('documentEmpty').textContent = error ? 'صحح نطاق التاريخ لعرض النتائج.' : data.vehicles.length ? 'لا توجد وثائق تطابق الفلاتر المحددة.' : 'لا توجد سيارات متاحة لك.';
    $('documentRules').textContent = data.settings.map(s => `${documentKinds[s.kind]}: قبل ${s.days_before} يوم`).join(' · ');
  }
  for (const id of ['documentVehicle','documentDriver','documentKind','documentState','documentDateFrom','documentDateTo']) $(id).onchange = render;
  $('documentSearch').oninput = render;
  $('clearDocumentFilters').onclick = () => {
    for (const id of ['documentVehicle','documentDriver','documentKind','documentState','documentSearch','documentDateFrom','documentDateTo']) $(id).value = '';
    const url = new URL(location.href);url.searchParams.delete('vehicle');history.replaceState(null,'',url);
    render();
  };
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
          $("fleetDialog").close();
          $("fleetStatus").textContent =
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
      `<div class="fleet-form">${data.settings.map((s) => `<form class="fleet-card" data-setting-kind="${s.kind}"><label>${documentKinds[s.kind]} — أيام قبل الانتهاء<input lang="en" name="days" type="number" min="0" max="3650" step="1" value="${s.days_before}" required></label><button class="fleet-btn" type="submit">حفظ مدة التنبيه</button></form>`).join("")}</div>`,
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
          $("fleetDialog").close();
          $("fleetStatus").textContent =
            "تم حفظ مدة التنبيه وتطبيقها على الوثائق.";
        });
  };
  await load();
  if (new URLSearchParams(location.search).get("view") === "documents")
    document.querySelector("[data-tab=documents]").click();
}
