import {readAllRows} from './paged-read.mjs?v=2.5.57';
import {escape,indicatorName} from './kpi-measurement-core.mjs?v=1.0.0';
export function createTaskMeasurementLinks({getClient,currentTask,hostId='detailMeasurementSources'}){
 let selected=null,generation=0,lastRead=0,pending=false;
 return {async show(task){
  const host=document.getElementById(hostId);if(!host)return;
  if(task?.id===selected&&(pending||Date.now()-lastRead<60000))return;
  const token=++generation;selected=task?.id||null;host.hidden=!task;host.innerHTML='';if(!task){pending=false;return;}
  pending=true;host.innerHTML='<p class="text-xs" role="status">جاري تحميل سجلات القياس المرتبطة…</p>';
  try{const sb=await getClient();const rows=await readAllRows(()=>sb.from('kpi_measurements').select('id,employee_id,indicator_snapshot,period_start,period_end').eq('task_id',task.id).order('id'));if(token!==generation||currentTask()?.id!==task.id)return;
   host.hidden=!rows.length;host.innerHTML=rows.length?'<h3 class="text-sm font-bold">سجلات قياس مرتبطة بهذه المهمة</h3>'+rows.map(r=>`<a class="block text-xs py-2" href="../profile/measurements.html?employee=${encodeURIComponent(r.employee_id)}&record=${encodeURIComponent(r.id)}">${escape(indicatorName(r.indicator_snapshot))} · ${escape(r.period_start)} — ${escape(r.period_end)}</a>`).join(''):'';lastRead=Date.now();
  }catch{if(token===generation){host.hidden=false;host.innerHTML='<p class="text-xs" role="status">تعذر تحميل سجلات القياس المرتبطة.</p>';lastRead=Date.now();}}
  finally{if(token===generation)pending=false;}
 }};
}
