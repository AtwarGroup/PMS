export const states={PLANNING:'تخطيط',ACTIVE:'تنفيذ',PAUSED:'متوقف مؤقتًا',CLOSED:'مغلق',CANCELLED:'ملغى'};
export const health={ON_TRACK:'على المسار',AT_RISK:'معرض للتأخر',BLOCKED:'متعثر'};
export const taskStates=['قيد الانتظار','قيد التنفيذ','بانتظار الاعتماد','مكتملة'];
export const day=value=>Date.parse(value+'T00:00:00Z')/86400000;
export function weightedProgress(tasks){const active=tasks.filter(t=>t.status!=='ملغاة'&&!t.deleted_at);const weight=active.reduce((n,t)=>n+Number(t.project_weight||1),0);if(!weight)return 0;const result=Math.round(active.reduce((n,t)=>n+Number(t.project_weight||1)*(t.status==='مكتملة'?100:Math.min(99,Number(t.progress||0))),0)/weight);return active.every(t=>t.status==='مكتملة')?100:Math.min(99,result);}
export function timeline(tasks,project,scale='week'){
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Riyadh',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const start=day(project.start_date),end=day(project.due_date),days=Math.max(1,end-start+1),unit=({day:42,week:12,month:4})[scale]||12;
 return {days,width:Math.max(600,days*unit),rows:tasks.map(t=>({id:t.id,left:Math.max(0,(day(t.start_date)-start)/days*100),width:Math.max(.3,(day(t.due_date)-day(t.start_date)+1)/days*100),late:!t.deleted_at&&['قيد الانتظار','قيد التنفيذ'].includes(t.status)&&!!t.due_date&&t.due_date<today}))};
}
export function dependencyImpact(taskId,dependencies,tasks){const found=new Set(),queue=[taskId];while(queue.length){const id=queue.shift();for(const d of dependencies.filter(d=>d.predecessor_id===id)){if(!found.has(d.task_id)){found.add(d.task_id);queue.push(d.task_id);}}}return tasks.filter(t=>found.has(t.id));}
export function validDates(start,end){return [start,end].every(v=>/^\d{4}-\d{2}-\d{2}$/.test(v||'')&&Number.isFinite(day(v))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v)&&end>=start;}
