export { escapeHTML } from "./access-model.mjs";
export const states = {
  draft: "مسودة",
  returned: "معاد للتعديل",
  quote_exception: "اعتماد استثناء العروض",
  manager_review: "اعتماد المدير المباشر",
  fleet_review: "مراجعة مسؤول الأسطول",
  awaiting_advance: "بانتظار الصرف",
  repair: "قيد الإصلاح",
  increase_review: "اعتماد الزيادة",
  reimbursement: "بانتظار الاستعاضة",
  settlement: "بانتظار التسوية",
  closed: "مغلق",
  rejected: "مرفوض نهائيًا",
};
export const types = {
  repair: "صيانة",
  emergency: "عطل طارئ",
};
export const actions = {
  submit: "إرسال الطلب",
  approve_exception: "اعتماد الاستثناء",
  approve: "اعتماد",
  request_increase: "طلب اعتماد زيادة",
  approve_increase: "اعتماد الزيادة",
  decline_increase: "رفض الزيادة",
  confirm_repair: "تأكيد الإصلاح والاستلام",
  confirm_advance: "تأكيد الصرف",
  settle: "تأكيد الاستعاضة / التسوية",
  return: "إعادة للتعديل",
  reject: "رفض نهائي",
};
export const money = (value) =>
  Number(value || 0).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
export const quoteTotal = (q) =>
  Math.round(
    (Number(q.parts || 0) + Number(q.labor || 0) + Number(q.tax || 0)) * 100,
  ) / 100;
export function requestActions(r, c) {
  const own = r.driver_id === c.employee_id,
    finance = (r.accountant_id === c.user_id || c.is_admin) && c.can_finance && !own;
  if (["closed", "rejected"].includes(r.state)) return [];
  let list = [];
  if ((own || c.can_operate || (c.team_employee_ids || []).includes(r.driver_id)) && ["draft", "returned"].includes(r.state)) list = ["edit", "submit"];
  if ((own || c.can_operate) && r.state === "repair")
    list = ["request_increase", "confirm_repair"];
  if (!own && r.state === "manager_review" && (r.manager_id === c.user_id || c.can_operate))
    list = ["approve", "return", "reject"];
  if (
    !own &&
    c.can_approve &&
    ["quote_exception", "fleet_review", "increase_review"].includes(r.state)
  )
    list = [
      r.state === "quote_exception"
        ? "approve_exception"
        : r.state === "increase_review"
          ? "approve_increase"
          : "approve",
      ...(r.state === "increase_review" ? ["decline_increase"] : []),
      "return",
      ...(Number(r.advance) > 0 ? [] : ["reject"]),
    ];
  if (
    finance &&
    ["awaiting_advance", "reimbursement", "settlement"].includes(r.state)
  )
    list = [
      r.state === "awaiting_advance" ? "confirm_advance" : "settle",
      "return",
      ...(Number(r.advance) > 0 ? [] : ["reject"]),
    ];
  return list;
}
export function filterRequests(
  rows,
  { query = "", state = "", vehicle = "" } = {},
) {
  const q = query.trim().toLocaleLowerCase("ar");
  return rows.filter(
    (r) =>
      (!state || r.state === state) &&
      (!vehicle || r.vehicle_id === vehicle) &&
      (!q ||
        [r.number, r.description, r.driver_name, r.plate].some((v) =>
          String(v ?? "")
            .toLocaleLowerCase("ar")
            .includes(q),
        )),
  );
}
export function summary(rows) {
  const closed = rows.filter((r) => r.state === "closed");
  return {
    open: rows.filter((r) => !["draft", "closed", "rejected"].includes(r.state))
      .length,
    closed: closed.length,
    cost: closed.reduce((n, r) => n + Number(r.invoice_total), 0),
    outstanding: rows
      .filter((r) => r.state !== "closed")
      .reduce((n, r) => n + Number(r.advance), 0),
  };
}
export function settlement(r) {
  const amount =
    Math.round((Number(r.invoice_total) - Number(r.advance)) * 100) / 100;
  return {
    amount: Math.abs(amount),
    kind: amount < 0 ? "refund" : amount > 0 ? "payment" : "none",
    label:
      amount < 0
        ? "استرداد المتبقي من السائق"
        : amount > 0
          ? r.route === "small"
            ? "استعاضة للسائق"
            : "صرف الفرق للسائق"
          : "تسوية دون فرق مالي",
  };
}

export const englishDigits = value => String(value ?? '').replace(/[٠-٩۰-۹]/g, c => String('٠١٢٣٤٥٦٧٨٩'.includes(c) ? '٠١٢٣٤٥٦٧٨٩'.indexOf(c) : '۰۱۲۳۴۵۶۷۸۹'.indexOf(c)));
export function dashboardRequests(context, scope) {
 if(scope==='personal')return context.requests.filter(r=>r.driver_id===context.employee_id);
 if(scope==='team')return context.requests.filter(r=>(context.team_employee_ids||[]).includes(r.driver_id));
 return context.requests;
}
