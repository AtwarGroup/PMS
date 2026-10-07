export function promptTaskReschedule(task){
 return new Promise(resolve=>{
  const dialog=document.createElement('dialog');
  dialog.className='atwar-reschedule-dialog';dialog.dir='rtl';dialog.setAttribute('aria-label','طلب إعادة جدولة المهمة');
  dialog.innerHTML=`<form><h2>طلب إعادة جدولة المهمة</h2><p>تبقى المواعيد الحالية سارية حتى موافقة منشئ المهمة.</p><div class="reschedule-dates"><label>تاريخ البداية المقترح<input name="start" type="date" required></label><label>تاريخ الانتهاء المقترح<input name="due" type="date" required></label></div><label>سبب إعادة الجدولة<textarea name="reason" rows="3" minlength="3" maxlength="1000" required placeholder="وضح سبب التغيير المطلوب"></textarea></label><p class="reschedule-error" role="alert"></p><footer><button type="submit" class="atwar-btn primary">إرسال الطلب</button><button type="button" class="atwar-btn" data-cancel>إلغاء</button></footer></form>`;
  const form=dialog.querySelector('form'),fields=form.elements;fields.start.value=task.start||'';fields.due.value=task.end||'';
  let settled=false;const done=value=>{if(settled)return;settled=true;dialog.close();dialog.remove();resolve(value);};
  form.onsubmit=e=>{e.preventDefault();if(!form.reportValidity())return;const start=fields.start.value,due=fields.due.value,reason=fields.reason.value.trim();if(due<start||reason.length<3){dialog.querySelector('.reschedule-error').textContent=due<start?'تاريخ الانتهاء يجب ألا يسبق البداية.':'يرجى توضيح سبب الطلب.';return;}done({start,due,reason});};
  dialog.querySelector('[data-cancel]').onclick=()=>done(null);dialog.addEventListener('cancel',e=>{e.preventDefault();done(null);});dialog.addEventListener('keydown',e=>{if(e.key==='Escape')e.stopPropagation();});document.body.append(dialog);dialog.showModal();fields.start.focus();
 });
}
