import {escapeHTML} from './tasks-core.mjs?v=1.9.8';
import {normalizeFollowup} from './task-followup-core.mjs?v=1.0.0';
export function createTaskFollowupController({getClient,currentTask,hostId='taskFollowupDetails'}){
 let taskId=null,context=null,generation=0,dirty=false,saving=false;const drafts=new Map(),el=id=>document.getElementById(id);
 const values=()=>({blocked:el('tfBlocked').checked,reason:el('tfReason').value,next_step:el('tfNext').value,owner_role:el('tfOwner').value,follow_date:el('tfDate').value});
 function permissions(task){const allowed=!!context?.can_edit&&['قيد الانتظار','قيد التنفيذ'].includes(task?.status);for(const id of ['tfBlocked','tfReason','tfNext','tfOwner','tfDate','tfSave'])if(el(id))el(id).disabled=!allowed||saving;return allowed;}
 function render(task,data){
  const host=el(hostId),f=data||{};host.innerHTML=`<h3 class="text-sm font-black mb-2">متابعة التنفيذ</h3><p class="text-xs text-slate-500 mb-3">اختياري: وضّح العائق والإجراء التالي وموعد الرجوع إليه.</p><form id="tfForm" class="space-y-3"><label class="flex items-center gap-2 text-sm"><input type="checkbox" id="tfBlocked" ${f.blocked?'checked':''}> يوجد عائق يمنع استمرار التنفيذ</label><label class="block text-xs font-bold">سبب التعثر<textarea id="tfReason" maxlength="1000" rows="2" class="w-full border rounded-lg p-2 mt-1">${escapeHTML(f.reason||'')}</textarea></label><label class="block text-xs font-bold">الإجراء التالي<textarea id="tfNext" maxlength="1000" rows="2" class="w-full border rounded-lg p-2 mt-1">${escapeHTML(f.next_step||'')}</textarea></label><div class="grid grid-cols-2 gap-3"><label class="block text-xs font-bold">صاحب الإجراء<select id="tfOwner" class="w-full border rounded-lg p-2 mt-1"><option value="assignee">المسند إليه</option><option value="creator">منشئ المهمة</option></select></label><label class="block text-xs font-bold">موعد المتابعة<input id="tfDate" type="date" value="${escapeHTML(f.follow_date||'')}" class="w-full border rounded-lg p-2 mt-1"></label></div><div class="flex gap-2"><button id="tfSave" type="submit" class="atwar-btn primary">حفظ المتابعة</button><button id="tfReload" type="button" class="atwar-btn">إعادة تحميل المتابعة</button></div><p id="tfStatus" role="status" aria-live="polite" class="text-xs text-slate-500"></p></form>`;
  el('tfOwner').value=f.owner_role||'assignee';permissions(task);el('tfStatus').textContent=context.can_edit?'':'المتابعة للقراءة فقط في حالتها الحالية.';
  el('tfForm').addEventListener('input',()=>{dirty=true;el('tfStatus').textContent='تعديلات غير محفوظة';});
  el('tfReload').onclick=()=>{drafts.delete(taskId);dirty=false;taskId=null;void show(currentTask());};
  el('tfForm').onsubmit=async event=>{
   event.preventDefault();if(saving||!permissions(currentTask()))return;
   const selected=taskId,version=generation,expected=context;let input;
   try{input=normalizeFollowup(values());}catch(e){el('tfStatus').textContent=e.message;return;}
   saving=true;permissions(currentTask());el('tfStatus').textContent='جاري حفظ المتابعة…';
   try{const sb=await getClient();const {data,error}=await sb.rpc('save_task_followup',{p_task_id:selected,p_blocked:input.blocked,p_reason:input.reason,p_next_step:input.next_step,p_owner_role:input.owner_role,p_follow_date:input.follow_date,p_expected_revision:expected.followup?.revision||0,p_expected_task_revision:expected.task_revision});if(error)throw error;drafts.delete(selected);if(version!==generation||selected!==currentTask()?.id)return;context=data;dirty=false;el('tfStatus').textContent='تم حفظ المتابعة.';}
   catch(e){if(version===generation)el('tfStatus').textContent=String(e.message||'').includes('ATWAR_CONFLICT')?'تغيّرت المهمة أو المتابعة. أعد تحميلها قبل الحفظ؛ نصك الحالي لم يُحذف.':'تعذر الحفظ: '+(e.message||'حاول مرة أخرى.');}
   finally{saving=false;permissions(currentTask());}
  };
 }
 async function show(task){
  const host=el(hostId);if(!host)return;
  if(taskId===task?.id&&context){permissions(task);return;}
  if(dirty&&taskId&&el('tfForm'))drafts.set(taskId,{values:values(),context});
  const version=++generation;taskId=task?.id||null;context=null;dirty=false;host.hidden=!task||!!task.jobWorkflow;if(host.hidden){host.replaceChildren();return;}
  host.innerHTML='<p role="status" class="text-xs text-slate-500">جاري تحميل متابعة التنفيذ…</p>';
  try{const sb=await getClient();const {data,error}=await sb.rpc('task_followup_context',{p_task_id:task.id});if(error)throw error;if(version!==generation||currentTask()?.id!==task.id)return;const draft=drafts.get(task.id);context=draft?.context||data;render(task,draft?.values||data.followup);dirty=!!draft;if(draft)el('tfStatus').textContent='لديك تعديلات غير محفوظة.';}
  catch{if(version!==generation)return;host.innerHTML='<p role="status" class="text-xs text-slate-500">تعذر تحميل متابعة التنفيذ.</p><button id="tfRetry" type="button" class="atwar-btn">إعادة المحاولة</button>';el('tfRetry').onclick=()=>{taskId=null;void show(currentTask());};}
 }
 return {show};
}
