const uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const pattern=new RegExp('https://one\\.atwargroup\\.com/(tasks/index\\.html\\?task=|projects/index\\.html\\?id=|policies/index\\.html\\?id=)('+uuid+')(?![0-9a-z-])','gi');
export function workReferences(body){return [...String(body||'').matchAll(pattern)].slice(0,5).map(m=>({kind:m[1].startsWith('tasks')?'task':m[1].startsWith('projects')?'project':'policy',id:m[2].toLowerCase(),url:m[0]}));}
export function workURL(kind,id){if(!new RegExp('^'+uuid+'$','i').test(id))throw Error('مرجع غير صحيح');const path={task:'tasks/index.html?task=',project:'projects/index.html?id=',policy:'policies/index.html?id='}[kind];if(!path)throw Error('نوع غير صحيح');return 'https://one.atwargroup.com/'+path+encodeURIComponent(id);}
export async function resolveWorkReferences(sb,refs){
 const out=new Map();for(const kind of ['task','project','policy']){const ids=[...new Set(refs.filter(r=>r.kind===kind).map(r=>r.id))];if(!ids.length)continue;
 for(let offset=0;offset<ids.length;offset+=100){const batch=ids.slice(offset,offset+100);let q=sb.from({task:'tasks',project:'projects',policy:'policies'}[kind]).select('id,title'+(kind==='policy'?'':',status')).in('id',batch);if(kind!=='policy')q=q.is('deleted_at',null);const {data,error}=await q;
 for(const id of batch)out.set(kind+':'+id,error?{error:true}:(data||[]).find(r=>r.id===id)||{restricted:true});}}return out;
}
