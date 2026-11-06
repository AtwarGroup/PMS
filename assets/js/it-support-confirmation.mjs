import {esc} from './it-support-model.mjs?v=7';
const date=value=>new Date(value).toLocaleString('ar-SA-u-nu-latn',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Riyadh'});
export function confirmationHTML(t){
 if(t.service_key==='purchase')return '';
 if(t.state==='resolved'&&t.auto_close_at)return `<section class="rec-card" aria-label="مهلة تأكيد الحل"><h3>تأكيد الحل قبل الإغلاق التلقائي</h3><p>يُغلق الطلب تلقائيًا بعد 48 ساعة عمل دون إجراء منك.</p><p>موعد الإغلاق: <strong>${esc(date(t.auto_close_at))}</strong> بتوقيت الرياض.</p><p>أيام العمل من السبت إلى الخميس، والجمعة والإجازات وخارج الدوام لا تدخل في الحساب. يصلك تذكير قبل الإغلاق بـ24 ساعة عمل.</p><p>اختر «تأكيد الحل وإغلاق الطلب» أو «المشكلة لم تُحل» لإعادته للمعالجة. ردك يجدد المهلة.</p></section>`;
 if(t.state==='closed'&&t.auto_closed_at)return `<section class="rec-card" aria-label="إغلاق تلقائي"><h3>أُغلق الطلب تلقائيًا</h3><p>انتهت مهلة تأكيد الحل دون إجراء في ${esc(date(t.auto_closed_at))} بتوقيت الرياض. لم يُسجّل تقييم خدمة بالنيابة عنك.</p><p>يمكنك إعادة فتح الطلب إذا استمرت المشكلة.</p></section>`;
 return '';
}
