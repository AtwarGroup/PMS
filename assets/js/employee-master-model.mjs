export const domains={records:'البيانات الوظيفية',personal:'البيانات الشخصية',salary:'الرواتب',vehicles:'المركبات'};
export const escapeHTML=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function filterEmployees(rows,{query='',department='',section='',login=''}={}){
 const q=query.trim().toLocaleLowerCase('ar');
 return rows.filter(r=>(!q||[r.full_name,r.employee_code,r.title,r.manager,r.department,r.section].some(x=>String(x??'').toLocaleLowerCase('ar').includes(q)))&&(!department||r.department===department)&&(!section||r.section===section)&&(!login||(login==='active'?r.login_active:login==='waiting'?!r.profile_id:!!r.profile_id&&!r.login_active)));
}
export function normalizeGrant({read,write,scope}){return{read:!!(read||write),write:!!write,scope:scope==='all'?'all':'team'};}

// Build only from records already authorized by employee_master_list.
// Missing managers remain outside this forest; never fetch them by name or code.
export function employeeForest(rows){
 const byCode=new Map(rows.map(r=>[String(r.employee_code),r]));
 const children=new Map(rows.map(r=>[r.id,[]])),parent=new Map();
 for(const r of rows){const manager=byCode.get(String(r.manager_code||''));if(manager&&manager.id!==r.id){parent.set(r.id,manager.id);children.get(manager.id).push(r);}}
 const seen=new Set();
 function node(r){if(seen.has(r.id))return null;seen.add(r.id);return {record:r,children:children.get(r.id).map(node).filter(Boolean)};}
 const roots=rows.filter(r=>!parent.has(r.id)).map(node);
 // Corrupt or partial historical relationships must not hide a visible employee.
 for(const r of rows)if(!seen.has(r.id))roots.push(node(r));
 return roots;
}
export function employeePage(rows,page=1,size=25){size=[10,25,50].includes(Number(size))?Number(size):25;const pages=Math.max(1,Math.ceil(rows.length/size));page=Math.min(pages,Math.max(1,Number(page)||1));return {rows:rows.slice((page-1)*size,page*size),page,pages,total:rows.length,from:rows.length?(page-1)*size+1:0,to:Math.min(page*size,rows.length)};}
