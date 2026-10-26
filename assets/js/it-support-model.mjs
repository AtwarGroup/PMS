export const states={approval:'بانتظار الاعتماد',new:'جديد',working:'قيد المعالجة',waiting_employee:'بانتظار الموظف',waiting_vendor:'بانتظار المورد',resolved:'تم الحل',closed:'مغلق',cancelled:'ملغى',rejected:'مرفوض'};
export const priorities={1:'حرجة',2:'عالية',3:'عادية',4:'منخفضة'};
export const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const priority=(impact,urgency)=>impact===3&&urgency===3?1:impact+urgency>=5?2:impact+urgency>=3?3:4;
export const terminal=s=>['closed','cancelled','rejected'].includes(s);
export function actions(t,c){const a=[];const mine=[t.requester_id,t.beneficiary_id].includes(c.user_id);if(!terminal(t.state))a.push('comment');if(t.state==='approval'&&t.approver_id===c.user_id&&t.requester_id!==c.user_id)a.push('approve','reject');if(c.operator&&['new','working','waiting_employee','waiting_vendor'].includes(t.state))a.push('working','waiting_employee','waiting_vendor','resolve');if(mine&&t.state==='resolved')a.push('close');if(mine&&['resolved','closed'].includes(t.state)&&new Date(t.resolved_at)>new Date(Date.now()-5*86400000))a.push('reopen');if(t.requester_id===c.user_id&&['new','approval'].includes(t.state))a.push('cancel');return a;}

export const archived=s=>['resolved','closed','cancelled','rejected'].includes(s);
