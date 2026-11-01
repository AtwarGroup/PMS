export const states={new:'جديد',working:'جارٍ المعالجة',waiting_employee:'بانتظار معلومات إضافية',waiting_vendor:'تم تصعيد المشكلة',resolved:'تم الحل — بانتظار تأكيدك',closed:'مغلق',cancelled:'ملغى',rejected:'مرفوض'};
export const priorities={1:'طارئة (توقف العمل)',2:'عالية',3:'متوسطة',4:'عادية'};
export const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const priority=(i,u)=>i===3&&u===3?1:i+u>=5?2:i+u>=3?3:4;
export const terminal=s=>['closed','cancelled','rejected'].includes(s);
// Match fleet: closed requests remain visible for seven elapsed days.
export function archived(t,now=Date.now()){
 if(!terminal(t.state))return false;
 if(t.state!=='closed')return true;
 const completed=Date.parse(t.closed_at||t.updated_at||t.state_since);
 return !Number.isFinite(completed)||Number(now)>=completed+7*86400000;
}
export const targetLabels={1:'4 ساعات فعلية',2:'8 ساعات عمل',3:'يومان عمل',4:'5 أيام عمل'};
export function actions(t,c){if(t.service_key==='purchase')return[];const a=[];if(c.operator&&['new','working','waiting_employee','waiting_vendor'].includes(t.state))a.push('working','waiting_employee','waiting_vendor','resolve');if(c.operator&&!terminal(t.state))a.push('priority');if(t.state==='resolved'&&c.user_id===(t.beneficiary_id===t.specialist_id?t.supervisor_id:t.beneficiary_id))a.push('close');if(t.beneficiary_id===c.user_id&&['resolved','closed'].includes(t.state))a.push('reopen');if(t.requester_id===c.user_id&&['new','working','waiting_employee','waiting_vendor'].includes(t.state))a.push('cancel');return a;}
export function overdue(t,now=new Date()){return !!t.due_at&&t.service_key!=='purchase'&&!terminal(t.state)&&!['resolved','waiting_employee'].includes(t.state)&&+now>+new Date(t.due_at);}
export function delayDays(t,now=new Date()){if(!overdue(t,now))return 0;const day=v=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Riyadh',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(v));return Math.max(0,Math.round((Date.parse(day(now))-Date.parse(day(t.due_at)))/86400000));}
