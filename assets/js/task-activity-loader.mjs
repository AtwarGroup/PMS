import {readAllRows} from './paged-read.mjs?v=2.8.0';

export async function readTaskActivity(sb,taskId){
 if(!taskId)throw new Error('Task identifier unavailable');
 const rows=await readAllRows(()=>sb.from('task_activity').select('id,task_id,sequence_no,event_type,detail,actor_id,actor_name_snapshot,created_at').eq('task_id',taskId).order('sequence_no',{ascending:true}));
 return rows.map(a=>{const time=typeof a.created_at==='number'?a.created_at:new Date(a.created_at||0).getTime();return {type:a.event_type||'activity',detail:a.detail||'',userUid:a.actor_id||'',userName:a.actor_name_snapshot||'',createdAt:Number.isFinite(time)?time:0};});
}
// In-memory, task-object and identity-scoped. Refreshing task data invalidates its history.
export function createTaskActivityLoader({read,canRead,getScope,isCurrent,onChange}){
 const entries=new WeakMap();
 function state(task){
  if(!canRead())return {status:'denied',rows:[]};
  const entry=entries.get(task);if(entry?.scope===getScope())return entry;
  return {status:'idle',rows:[]};
 }
 function load(task,{retry=false}={}){
  if(!canRead())return Promise.resolve({status:'denied',rows:[]});
  const previous=state(task);if(previous.status==='loading'||(previous.status==='ready'&&!retry))return previous.promise||Promise.resolve(previous);
  const entry={status:'loading',rows:[],scope:getScope()};entries.set(task,entry);
  entry.promise=Promise.resolve().then(()=>{if(!canRead()||getScope()!==entry.scope)return null;return read(task);}).then(rows=>{
   if(rows===null||!canRead()||getScope()!==entry.scope){if(entries.get(task)===entry)entries.delete(task);return {status:'denied',rows:[]};}
   entry.status='ready';entry.rows=rows;if(isCurrent(task))onChange(task);return entry;
  },()=>{entry.status='error';entry.rows=[];if(canRead()&&getScope()===entry.scope&&isCurrent(task))onChange(task);return entry;});
  return entry.promise;
 }
 return {state,load};
}
