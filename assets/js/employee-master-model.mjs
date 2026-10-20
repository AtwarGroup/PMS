export const domains={records:'البيانات الوظيفية',personal:'البيانات الشخصية',salary:'الرواتب',vehicles:'المركبات'};
export const escapeHTML=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function filterEmployees(rows,{query='',department='',section='',login=''}={}){
 const q=query.trim().toLocaleLowerCase('ar');
 return rows.filter(r=>(!q||[r.full_name,r.employee_code,r.title,r.manager].some(x=>String(x??'').toLocaleLowerCase('ar').includes(q)))&&(!department||r.department===department)&&(!section||r.section===section)&&(!login||(login==='active'?r.login_active:!r.login_active)));
}
export function normalizeGrant({read,write,scope}){return{read:!!(read||write),write:!!write,scope:scope==='all'?'all':'team'};}
