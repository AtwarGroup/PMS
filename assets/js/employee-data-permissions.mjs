import {domains,escapeHTML as esc,normalizeGrant} from './employee-master-model.mjs?v=2.6.1';
const el=id=>document.getElementById(id);
const sb=await window.atwarGetSupabase();
let context;
const status=(message,error=false)=>{el('employeeAccessStatus').textContent=message;el('employeeAccessStatus').className='msg'+(error?' err':'');};
async function rpc(name,args){const {data,error}=await sb.rpc(name,args);if(error)throw Error(error.message);return data;}
function renderGrant(){const g=context.grants.find(x=>x.profile_id===el('grantProfile').value&&x.domain===el('grantDomain').value);el('grantRead').checked=!!g?.can_read;el('grantWrite').checked=!!g?.can_write;el('grantScope').value=g?.scope||'team';}
function listGrants(){el('grantList').innerHTML=`<ul>${context.grants.filter(g=>g.can_read).map(g=>`<li>${esc(context.users.find(x=>x.id===g.profile_id)?.name||'الحساب')} • ${esc(domains[g.domain])} • ${g.scope==='all'?'جميع الموظفين':'الموظف وفريقه'} • ${g.can_write?'عرض وتعديل':'عرض فقط'}</li>`).join('')||'<li>لم تُمنح صلاحيات إضافية بعد.</li>'}</ul>`;}
for(const id of ['grantProfile','grantDomain'])el(id).onchange=renderGrant;
el('grantWrite').onchange=()=>{if(el('grantWrite').checked)el('grantRead').checked=true;};
el('grantRead').onchange=()=>{if(!el('grantRead').checked)el('grantWrite').checked=false;};
el('accessForm').onsubmit=async event=>{
 event.preventDefault();if(!context?.admin)return;
 const fields=el('employeeAccessFields'),g=normalizeGrant({read:el('grantRead').checked,write:el('grantWrite').checked,scope:el('grantScope').value});
 fields.disabled=true;
 try{await rpc('employee_master_grant',{p_profile:el('grantProfile').value,p_domain:el('grantDomain').value,p_scope:g.scope,p_read:g.read,p_write:g.write});context=await rpc('employee_master_context');renderGrant();listGrants();status('تم تحديث الصلاحية.');}
 catch(e){status(e.message,true);}finally{fields.disabled=!context?.admin;}
};
try{
 context=await rpc('employee_master_context');
 if(!context.admin)throw Error('إدارة الصلاحيات متاحة لمسؤول النظام فقط.');
 el('grantProfile').innerHTML=context.users.map(u=>`<option value="${esc(u.id)}">${esc(u.name)}</option>`).join('');
 renderGrant();listGrants();el('employeeAccessFields').disabled=context.users.length===0;status(context.users.length?'':'لا توجد حسابات متاحة.');
}catch(e){status(e.message,true);}
