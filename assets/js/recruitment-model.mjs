export const stages = {
  screening: "الفرز الأولي",
  interview: "المقابلة",
  assessment: "التقييم",
  recommended: "موصى بالتعيين",
  offer: "العرض الوظيفي",
  accepted: "استكمال التعيين",
  hired: "باشر العمل",
  rejected: "مستبعد",
  withdrawn: "منسحب",
  no_show: "لم يباشر",
};
export const requestStates = {
  draft: "مسودة",
  department_review: "موافقة مدير الإدارة",
  hr_exception: "استثناء مشرف تطوير الأعمال",
  finance_exception: "استثناء الرئيس التنفيذي",
  cancellation_approval: "اعتماد إلغاء الطلب",
  hr_review: "مراجعة مسؤول التوظيف والتوطين",
  finance_review: "مراجعة الميزانية",
  approval: "اعتماد الاحتياج",
  open: "مفتوح",
  closed: "مكتمل",
  rejected: "مرفوض",
  cancelled: "ملغى",
};
export const routes = {
  advertised: "البحث عن مرشحين",
  referral: "مرشح مقدم من الإدارة",
};
export const escapeHTML = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
export const money = (v) =>
  v == null
    ? "غير مربوط"
    : new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(v) +
      " ر.س";
export function nextStages(stage) {
  return (
    {
      screening: ["interview"],
      interview: ["assessment"],
      assessment: ["recommended"],
      recommended: ["offer"],
      offer: ["accepted"],
      accepted: ["hired", "no_show"],
    }[stage] || []
  );
}
export function scoreResult(criteria, scores) {
  if (
    !criteria.length ||
    criteria.some(
      (c) =>
        !Number.isFinite(Number(scores[c.key])) ||
        Number(scores[c.key]) < 1 ||
        Number(scores[c.key]) > 5,
    )
  )
    return null;
  const weight = criteria.reduce((s, c) => s + Number(c.weight), 0);
  if (weight !== 100) return null;
  return Math.round(
    criteria.reduce((s, c) => s + Number(scores[c.key]) * Number(c.weight), 0) /
      5,
  );
}
export function dashboard(requests, applications) {
  return {
    open: requests.filter((r) => r.status === "open").length,
    pending: requests.filter((r) =>
      ["department_review", "hr_review", "finance_review", "approval", "hr_exception", "finance_exception", "cancellation_approval"].includes(r.status),
    ).length,
    interviews: applications.filter((a) => a.stage === "interview").length,
    hired: applications.filter((a) => a.stage === "hired").length,
  };
}
export const defaultCriteria = [
  { key: "experience", label: "الخبرة المرتبطة بالوظيفة", weight: 30 },
  { key: "technical", label: "المهارات الفنية المطلوبة", weight: 40 },
  { key: "communication", label: "التواصل والتعاون", weight: 20 },
  { key: "readiness", label: "الجاهزية لمتطلبات العمل", weight: 10 },
];
