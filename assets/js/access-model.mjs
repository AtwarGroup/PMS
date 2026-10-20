export const systemRoles={employee:'موظف',manager:'مدير',admin:'مسؤول النظام'};
export const escapeHTML=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
export const scopeName=s=>s==='all'?'جميع الموظفين / السجلات':'الموظف وفريقه الإداري';
export function assignedRoles(context,id){return context.assignments.filter(a=>a.profile_id===id).map(a=>a.role_id).sort();}
export function accessSources(context,user){
 const rows=[];
 for(const key of context.direct_tasks.find(d=>d.profile_id===user.id)?.permissions||[]){const c=context.catalog.find(c=>c.key===key);if(c)rows.push({...c,scope:c.scopes[0],source:'منح مباشر',enabled:!c.requires_manager||user.role==='manager'});}
 for(const g of context.direct_hr.filter(g=>g.profile_id===user.id))for(const op of ['read','write'])if(g['can_'+op]){const c=context.catalog.find(c=>c.domain===g.domain&&c.operation===op);if(c)rows.push({...c,scope:g.scope,source:'منح مباشر',enabled:true});}
 for(const id of assignedRoles(context,user.id)){const role=context.roles.find(r=>r.id===id);if(!role)continue;for(const g of role.rules){const c=context.catalog.find(c=>c.key===g.permission);if(c)rows.push({...c,scope:g.scope,source:role.name,enabled:role.active&&(!c.requires_manager||user.role==='manager')});}}
 return rows.map(r=>({...r,enabled:r.enabled&&user.active&&user.status==='active'}));
}
export function normalizeRules(rules){
 const map=new Map(rules.filter(r=>r.scope).map(r=>[r.permission,{...r}]));
 for(const r of [...map.values()])if(r.permission.endsWith('.write')){const key=r.permission.replace(/\.write$/,'.read'),read=map.get(key);if(!read||r.scope==='all')map.set(key,{permission:key,scope:r.scope});}
 return [...map.values()].sort((a,b)=>a.permission.localeCompare(b.permission));
}
export function filterUsers(users,{query='',role='',status=''}={}){const q=query.trim().toLocaleLowerCase('ar');return users.filter(u=>(!role||u.role===role)&&(!status||(status==='active'?u.active&&u.status==='active':!u.active||u.status!=='active'))&&(!q||[u.full_name,u.email,u.employee_code,u.job_title].some(v=>String(v||'').toLocaleLowerCase('ar').includes(q))));}
