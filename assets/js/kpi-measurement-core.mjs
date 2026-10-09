import {escapeHTML as escape} from './tasks-core.mjs?v=1.9.8';
export {escape};
export function normalizeMeasurement(value){
 const out={};
 for(const [key,max] of Object.entries({result_text:1000,source_text:2000,evidence_url:2000,evidence_note:2000,notes:2000})){
  out[key]=String(value[key]||'').trim();if(out[key].length>max)throw Error('النص أطول من الحد المسموح.');
 }
 if(!out.result_text)throw Error('اكتب النتيجة الفعلية قبل الحفظ.');
 for(const key of ['period_start','period_end']){const day=value[key];if(!/^\d{4}-\d{2}-\d{2}$/.test(day||'')||!Number.isFinite(Date.parse(day))||new Date(day).toISOString().slice(0,10)!==day)throw Error('حدد فترة قياس صحيحة.');out[key]=day;}
 if(out.period_end<out.period_start)throw Error('نهاية الفترة يجب ألا تسبق بدايتها.');
 if(out.evidence_url){try{const url=new URL(out.evidence_url);if(!['https:','http:'].includes(url.protocol)||/\s/.test(out.evidence_url)||url.username||url.password)throw Error();}catch{throw Error('رابط الدليل يجب أن يبدأ بـ https:// أو http:// دون بيانات دخول.');}}
 out.task_id=value.task_id||null;out.project_id=value.project_id||null;return out;
}
export const indicatorName=i=>i?.name||i?.title||'مؤشر دون عنوان';
export function filterMeasurements(rows,{search='',from='',to=''}={}){
 return rows.filter(r=>(!search||[indicatorName(r.indicator_snapshot),r.result_text,r.source_text].join(' ').includes(search.trim()))&&(!from||r.period_end>=from)&&(!to||r.period_start<=to));
}
export function renderMeasurementRows(rows){
 return rows.map(r=>`<article class="measurement-record"><div><h3>${escape(indicatorName(r.indicator_snapshot))}</h3><p>${escape(r.period_start)} — ${escape(r.period_end)} · إصدار الوصف ${r.job_revision}</p><p><b>المستهدف:</b> ${escape(r.indicator_snapshot.target||'غير محدد')} · <b>النتيجة:</b> ${escape(r.result_text)}</p><p><b>مصدر البيانات:</b> ${escape(r.source_text||'لم يُوثّق بعد')}</p><p><b>توثيق الدليل:</b> ${r.evidence_url||r.evidence_note||r.task_id||r.project_id?'مسجل':'لم يُوثّق بعد'}</p></div><button class="atwar-btn" type="button" data-measurement="${escape(r.id)}">عرض / تعديل</button></article>`).join('')||'<p class="measurement-empty">لا توجد نتائج قياس مطابقة.</p>';
}
