import {englishDigits} from './fleet-model.mjs?v=20261101.1';
const normalizePlate = value => englishDigits(value).replace(/\s+/g, '').toLocaleLowerCase('ar');
export const documentKinds = {
  authorization: 'تفويض السائق',
  registration: 'رخصة السير',
  insurance: 'التأمين',
  inspection: 'الفحص الدوري',
};
export const documentStates = {
  valid: 'سارية — أكثر من 45 يومًا',
  warning: 'قرب الانتهاء — من 45 إلى 16 يومًا',
  urgent: 'عاجلة — من 15 يومًا حتى الانتهاء',
  expired: 'منتهية',
  missing: 'غير مسجلة',
};
export function documentState(document) {
  if (!document || document.days_left == null || !Number.isFinite(Number(document.days_left))) return 'missing';
  const days = Number(document.days_left);
  return days < 0 ? 'expired' : days <= 15 ? 'urgent' : days <= 45 ? 'warning' : 'valid';
}
export function validDocumentDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const time = Date.parse(value + 'T00:00:00Z');
  return Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === value;
}
export function documentDateError({from = '', to = ''}) {
  if ((from && !validDocumentDate(from)) || (to && !validDocumentDate(to))) return 'أدخل تاريخ انتهاء صالحًا.';
  return from && to && from > to ? 'يجب أن يكون تاريخ «إلى» مساويًا لتاريخ «من» أو بعده.' : '';
}
export function filterDocumentVehicles(data, filters = {}) {
  if (documentDateError(filters)) return [];
  const {vehicle = '', driver = '', query = '', kind = '', state = '', from = '', to = ''} = filters;
  const search = normalizePlate(query.trim());
  const byVehicle = new Map();
  for (const d of data.documents) {
    if (!byVehicle.has(d.vehicle_id)) byVehicle.set(d.vehicle_id, new Map());
    byVehicle.get(d.vehicle_id).set(d.kind, d);
  }
  return data.vehicles.flatMap(v => {
    if (vehicle && v.id !== vehicle) return [];
    if (driver && (v.driver_name || '__unassigned__') !== driver) return [];
    const plate = normalizePlate(v.plate);
    if (search && !plate.includes(search)) return [];
    const documents = byVehicle.get(v.id) || new Map();
    const matches = Object.keys(documentKinds).filter(k => !kind || k === kind).map(k => documents.get(k)).filter(d => {
      if (state && documentState(d) !== state) return false;
      if (from || to) return Boolean(d?.expires_on && (!from || d.expires_on >= from) && (!to || d.expires_on <= to));
      return true;
    });
    if (!matches.length) return [];
    const priority = {missing: -1, valid: 0, warning: 1, urgent: 2, expired: 3};
    const rowState = matches.map(documentState).reduce((a, b) => priority[b] > priority[a] ? b : a, 'missing');
    return [{vehicle: v, documents, state: rowState}];
  });
}
