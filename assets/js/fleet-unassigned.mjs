const reasons={reserve:'احتياط',maintenance:'صيانة',reassign:'بانتظار إعادة الإسناد',sale_pending:'بانتظار البيع',for_sale:'معروضة للبيع'};
const issues={loss:'فقد أو سرقة',damage:'تلف',unsafe:'موقع غير آمن'};
const date=value=>value?new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Riyadh'}).format(new Date(value)):'—';

async function evidence(file){
 if(!file)return null;
 if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>15*1024*1024)throw Error('اختر صورة JPEG أو PNG أو WebP حتى 15 ميجابايت.');
 const bitmap=await createImageBitmap(file);
 try{
  const canvas=document.createElement('canvas'),scale=Math.min(1,1280/Math.max(bitmap.width,bitmap.height));
  canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
  canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);
  return canvas.toDataURL('image/jpeg',0.78).split(',')[1];
 }finally{bitmap.close();}
}

export function initUnassigned({rpc,show,run,esc,load,status}){
 const section=document.getElementById('unassignedFollowup');
 let data;
 const call=(p_operation,p_vehicle=null,p_data={})=>rpc('fleet_unassigned_followup',{p_operation,p_vehicle,p_data});
 const btn=(label,attrs)=>`<button type="button" class="fleet-btn secondary" ${attrs}>${esc(label)}</button>`;
 const labels=(row,today)=>[
  row.issue&&issues[row.issue],!row.location&&'الموقع غير مؤكد',!row.verified_at&&'لم يتم التحقق',
  row.check_due<today&&'تحقق متأخر',row.action_due&&row.action_due<today&&'إجراء متأخر',!row.next_action&&'الإجراء غير محدد'
 ].filter(Boolean);
 async function refresh(context){
  section.hidden=!(context.can_correct||context.supervised_owner_id);
  if(section.hidden)return;
  try{
   data=await call('list');
   const rows=data.rows.sort((a,b)=>Number(Boolean(b.issue))-Number(Boolean(a.issue))
    ||Number(Boolean(labels(b,data.today).length))-Number(Boolean(labels(a,data.today).length))
    ||(a.started_at||'').localeCompare(b.started_at||'')||a.plate.localeCompare(b.plate,'ar'));
   section.innerHTML=`<header class="fleet-card-heading"><div><h2>السيارات غير المسندة <span class="fleet-muted">(${rows.length})</span></h2><p class="fleet-muted">المتابعة على مسؤول الأسطول. جهة التواصل في الموقع اختيارية ولا تُسند إليها العهدة.</p></div></header>${
    rows.length?`<div class="fleet-table-wrap"><table><thead><tr><th>السيارة / منذ</th><th>الموقع والسبب</th><th>التحقق</th><th>الإجراء القادم</th><th>المتابعة</th></tr></thead><tbody>${rows.map(r=>`<tr><td><b>${esc(r.plate)}</b><small>${r.started_at?date(r.started_at):'تاريخ فك الإسناد غير موثّق'}</small></td><td>${esc(r.location||'غير مؤكد')}<small>${esc(reasons[r.reason]||'السبب غير محدد')}${r.listing?' · '+esc(r.listing):''}</small></td><td>آخر تحقق: ${date(r.verified_at)}<small>القادم: ${date(r.check_due)}</small></td><td>${esc(r.next_action||'غير محدد')}<small>${date(r.action_due)}</small></td><td>${labels(r,data.today).map(s=>`<small class="fleet-tag rejected">${esc(s)}</small>`).join('')}${btn(data.writable?'متابعة':'عرض',`data-unassigned="${esc(r.vehicle_id)}"`)}</td></tr>`).join('')}</tbody></table></div>`:'<p class="fleet-muted">لا توجد سيارات غير مسندة تحتاج إلى متابعة.</p>'}`;
  }catch{
   data=null;section.innerHTML='<h2>السيارات غير المسندة</h2><p>تعذر تحميل قائمة المتابعة. حدّث الصفحة وأعد المحاولة.</p>';
  }
 }
 async function open(id,vehicle){
  const release=Boolean(vehicle),r=release?{plate:vehicle.plate,vehicle_id:vehicle.id,revision:vehicle.revision}:data?.rows.find(row=>row.vehicle_id===id);
  if(!r)throw Error('متابعة هذه السيارة غير متاحة.');
  const canEdit=release||data.writable;
  const input=(name,label,value='',extra='')=>`<label>${label}<input name="${name}" value="${esc(value??'')}" ${extra}></label>`;
  const select=(name,label,items,value,required)=>`<label>${label}<select name="${name}" ${required?'required':''}><option value="">${required?'اختر':'لا يوجد'}</option>${Object.entries(items).map(([key,title])=>`<option value="${key}" ${key===value?'selected':''}>${title}</option>`).join('')}</select></label>`;
  show(release?'فك إسناد السيارة · '+r.plate:'متابعة السيارة · '+r.plate,
   'مسؤول الأسطول يتولى المتابعة. جهة التواصل لا تتحمل عهدة السيارة.',
   `<p>آخر تحقق موثق: <b>${date(r.verified_at)}</b> · القادم: <b>${date(r.check_due)}</b></p>
   ${r.verified_at?btn('عرض آخر صورة','id="unassignedPhoto"'):''}<div id="unassignedEvidence"></div>
   <form id="unassignedForm"><fieldset class="fleet-form" ${canEdit?'':'disabled'}>
   ${release?input('release_note','توثيق استلام السيارة من السائق ومرجع التسليم','','required minlength="5" maxlength="500"'):''}
   ${input('location','الموقع الفعلي (اتركه فارغًا إذا لم يُؤكّد)',r.location,'maxlength="300"')}
   ${input('contact','جهة التواصل في الموقع (اختيارية)',r.contact,'maxlength="200"')}
   ${select('reason','سبب عدم الإسناد',reasons,r.reason,true)}
   ${input('listing','جهة العرض أو رابط الإعلان (إلزامي عند العرض للبيع)',r.listing,'maxlength="500"')}
   ${input('next_action','الإجراء القادم',r.next_action,'required minlength="3" maxlength="500"')}
   ${input('action_due','موعد الإجراء',r.action_due,'type="date" required')}
   ${select('issue','بلاغ عاجل',issues,r.issue,false)}
   ${input('issue_note','تفاصيل البلاغ',r.issue_note,'maxlength="500"')}
   ${canEdit?`<label>صورة حديثة للتحقق<input type="file" name="photo" accept="image/jpeg,image/png,image/webp"></label>
   ${input('note','ملاحظة الحالة أو تفاصيل التسليم','','maxlength="500"')}
   <p class="fleet-wide fleet-muted">الصورة والموقع وملاحظة الحالة مطلوبة لاحتساب التحقق وبدء أسبوع جديد.</p>
   <div class="fleet-wide fleet-action-buttons"><button class="fleet-btn" type="submit" value="save">${release?'تأكيد فك الإسناد':'حفظ المتابعة'}</button>${r.reason==='for_sale'?'<button class="fleet-btn secondary" type="submit" value="sold">توثيق تسليم السيارة المباعة</button>':''}</div>`:''}
   </fieldset></form>`);
  const photoBtn=document.getElementById('unassignedPhoto');
  if(photoBtn)photoBtn.onclick=e=>run(e,async()=>{
   const proof=await call('photo',id);
   if(!proof)throw Error('لا توجد صورة تحقق متاحة.');
   const img=document.createElement('img');img.src='data:image/jpeg;base64,'+proof.base64;img.alt='صورة آخر تحقق للسيارة';img.style.maxWidth='100%';
   const note=document.createElement('p');note.textContent=proof.note;
   document.getElementById('unassignedEvidence').replaceChildren(img,note);status('',false,true);
  });
  if(canEdit)document.getElementById('unassignedForm').onsubmit=e=>run(e,async()=>{
   const form=e.target,operation=release?'release':e.submitter?.value==='sold'?'sold':'save';
   const payload=Object.fromEntries(new FormData(form));payload.photo=await evidence(payload.photo?.size?payload.photo:null);payload.revision=r.revision;
   await call(operation,r.vehicle_id,payload);await load();document.getElementById('fleetDialog').close();
   status(operation==='sold'?'تم توثيق التسليم وإيقاف متابعة السيارة.':'تم حفظ متابعة السيارة.');
  });
 }
 section?.addEventListener('click',e=>{
  const trigger=e.target.closest('[data-unassigned]');if(trigger)open(trigger.dataset.unassigned).catch(error=>status(error.message,true));
 });
 return {refresh,open};
}
