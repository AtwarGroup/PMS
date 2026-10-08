import {renderJobLifecycle} from './job-lifecycle-view.mjs?v=2.5.59';
import {jobStage,publicationChanges,riyadhToday,periodicDue} from './job-workflow-model.mjs?v=2.5.59';
const sb = await window.atwarGetSupabase();
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const byId = id => document.getElementById(id);
const asArray = value => Array.isArray(value) ? value : [];
const itemText = value => typeof value === 'string' ? value : (value?.text || value?.name || '');
const statusLabels = {DRAFT:'مسودة',IN_REVIEW:'قيد المراجعة',CHANGES_REQUESTED:'تحتاج تعديل',MANAGER_APPROVED:'موافقة المدير مكتملة',PUBLISHED:'منشورة',ARCHIVED:'مؤرشفة'};
const sectionLabels = {PURPOSE:'الغرض الوظيفي',RESPONSIBILITIES:'المهام والمسؤوليات',AUTHORITIES:'الصلاحيات',KPIS:'مؤشرات الأداء',REPORTS:'التقارير والمخرجات',QUALIFICATIONS:'المؤهلات'};
let stagePermissions = new Set();let stageOwners=[];
const canStage=stage=>me?.role==='admin'||stagePermissions.has(stage);
let effectiveChoice='',lifecycleDirty=false,refreshingLifecycle=false;
let schedules=[],periodicReview=null,periodicEvents=[];
let session, me, job, users = [], assignments = [], proposals = [], forms = [], comments = [], weightReferences = [], versions = [], activeTab = 'overview', editing = false;

function toast(message) {
  const node = byId('toast');
  node.textContent = message;
  node.style.display = 'block';
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => node.style.display = 'none', 3200);
}

async function adminApi(body) {
  const config = window.ATWAR_SUPABASE_CONFIG;
  const response = await fetch(config.url + '/functions/v1/admin-create-user', {
    method: 'POST',
    headers: {'Content-Type':'application/json', Authorization:'Bearer ' + session.access_token, apikey:config.publishableKey},
    body: JSON.stringify(body)
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || 'تعذر تحميل بيانات الموظفين');
  return payload;
}

function managerReviewing() {
  return job.reviewer_id === me.id && job.status === 'IN_REVIEW';
}

function quality() {
  const content = job.content || {};
  const checks = [
    ['الغرض الوظيفي', (job.purpose || '').trim().length >= 40],
    ['مهام ومسؤوليات محددة', asArray(content.responsibilities).length >= 1],
    ['مصفوفة صلاحيات واضحة', asArray(content.authorities).length >= 1],
    ['مؤشرات أداء محددة', asArray(content.kpis).length >= 1],
    ['تقارير ومخرجات محددة', asArray(content.reports).length >= 1],
    ['مؤهلات الوظيفة', Boolean(content.qualifications?.education)]
  ];
  return {checks, score: Math.round(checks.filter(item => item[1]).length / checks.length * 100)};
}

function reviewerResolution() {
  const scheduled=openSchedule();if(scheduled)return {state:scheduled.status==='BLOCKED'?'danger':'approved',text:scheduled.status==='BLOCKED'?scheduled.note:`اعتمد الوصف ويبدأ سريانه في ${scheduled.effective_date}. تبقى النسخة السارية الحالية متاحة حتى الموعد.`};
  if(job.status === 'CHANGES_REQUESTED')return {state:'warning',text:'أعيد الوصف إلى الإعداد. السبب: '+(job.review_note||'راجع سجل القرارات')};
  if(job.status === 'MANAGER_APPROVED'&&job.final_reviewed_at)return {state:'approved',text:'اكتملت المراجعة النهائية. الحالة الآن: بانتظار الاعتماد والنشر.'};
  if(job.reviewer_mode==='override')return {state:'warning',text:'المراجع البديل: '+(users.find(x=>x.id===job.reviewer_id)?.full_name||'المكلّف')+' • السبب: '+job.reviewer_override_reason};
  if(job.status === 'MANAGER_APPROVED')return {state:'approved',text:'تمت مراجعة المدير وإرسال الوصف إلى مدير النظام. الحالة الآن: بانتظار المراجعة النهائية والاعتماد.'};
  if(job.status === 'PUBLISHED')return {state:'approved',text:'تم اعتماد الوصف ونشره، وهو ظاهر الآن للموظفين المرتبطين بهذه الوظيفة.'};
  if (!canStage('DRAFT') && !canStage('ASSIGN') && !canStage('FINAL_REVIEW') && !canStage('PUBLISH')) {
    if(job.reviewer_id === me.id && !me.manager_id)return {state:'',text:'أنت المراجع الأعلى لهذه الوظيفة. بعد استكمال المراجعة استخدم «إرسال لمدير النظام للاعتماد» لتنتقل مباشرة إلى مسؤول النظام.'};
    return job.reviewer_id === me.id
      ? {state:'', text:'أنت المدير المباشر المكلّف بمراجعة هذه الوظيفة، ويمكنك اقتراح تعديل أو حذف أو إضافة دون تغيير النسخة الرئيسية.'}
      : {state:'danger', text:'هذه الوظيفة ليست ضمن نطاق مراجعتك الحالي.'};
  }
  const linked = assignments.filter(item => item.job_description_id === job.id);
  const linkedUsers = linked.map(item => users.find(user => user.id === item.profile_id)).filter(Boolean);
  const managerIds = [...new Set(linkedUsers.map(user => user.manager_id).filter(Boolean))];
  const missing = linkedUsers.filter(user => !user.manager_id);
  if (!linkedUsers.length) return {state:'warning', text:job.reviewer_id?'المدير المباشر المراجع: '+(users.find(u=>u.id===job.reviewer_id)?.full_name||'المراجع المسجل'):'سيُحدد المدير المباشر من المرجعية التنظيمية عند الإرسال للمراجعة.'};
  if (missing.length && job.reviewer_id) {
    const explicitReviewer = users.find(user => user.id === job.reviewer_id)?.full_name || 'المراجع المعيّن';
    return {state:'', text:`لا يوجد مدير مباشر للموظف، لذلك سيُرسل الوصف إلى المراجع الذي عيّنه مسؤول النظام: ${explicitReviewer}.`};
  }
  if (missing.length) return {state:'danger', text:`يوجد ${missing.length} موظف دون مدير مباشر أو مراجع معيّن. يجب أن يختار مسؤول النظام المراجع قبل الإرسال.`};
  if (managerIds.length > 1 && !job.reviewer_id) return {state:'danger', text:'الموظفون المرتبطون بهذه الوظيفة يتبعون أكثر من مدير. يحدد مسؤول النظام مدير المراجعة المناسب.'};
  if (managerIds.length === 1 && job.reviewer_id && managerIds[0] !== job.reviewer_id) return {state:'danger', text:'المدير المراجع لا يطابق المدير المباشر المسجل للموظفين. الحالة محالة لمسؤول النظام.'};
  const name = users.find(user => user.id === (job.reviewer_id || managerIds[0]))?.full_name || 'المدير المسجل';
  return {state:'', text:`مرجع المراجعة التنظيمي هو المدير المباشر المسجل في الصلاحيات: ${name}.`};
}

function proposalActions(section, index) {
  if (!managerReviewing()) return '';
  return `<div class="item-actions"><button data-propose="MODIFY" data-section="${section}" data-index="${index}">اقتراح تعديل</button><button data-propose="DELETE" data-section="${section}" data-index="${index}">اقتراح حذف</button><button data-propose="COMMENT" data-section="${section}" data-index="${index}">إضافة ملاحظة</button></div>`;
}

function documentSection(mode){
 const snapshot={title:job.title,purpose:job.purpose,family:job.family,revision:job.revision,content:job.content};
 const view=window.AtwarJobDocument.section(mode,{job,snapshot,content:job.content||{},manager:users.find(user=>user.id===job.reviewer_id)});
 const template=document.createElement('div');template.innerHTML=view.html;
 const key={tasks:'RESPONSIBILITIES',authority:'AUTHORITIES',performance:'KPIS'}[mode];
 const items=mode==='performance'?template.querySelectorAll('.kpi-table tbody tr'):template.querySelectorAll('.authority-hybrid-list .hybrid-details');
 items.forEach((item,index)=>{const actions=proposalActions(key,index);if(actions){const target=mode==='performance'?item.children[1]:item.querySelector('.hybrid-details-body');target.insertAdjacentHTML('beforeend',actions);}});
 const add=managerReviewing()&&key?`<button class="review-btn" data-propose="ADD" data-section="${key}" data-index="-1">إضافة بند مقترح</button>`:'';
 if(mode==='tasks'&&managerReviewing()){
  const list=template.querySelector('.authority-hybrid-list');
  const responsibilityAdd='<button class="review-btn" data-propose="ADD" data-section="RESPONSIBILITIES" data-index="-1">إضافة مهمة أو مسؤولية مقترحة</button>';
  if(list)list.insertAdjacentHTML('afterend',responsibilityAdd);else template.insertAdjacentHTML('afterbegin',responsibilityAdd);
  template.querySelectorAll('.report-card').forEach((item,index)=>item.insertAdjacentHTML('beforeend',proposalActions('REPORTS',index)));
  if(!template.querySelector('.report-grid'))template.insertAdjacentHTML('beforeend','<div class="hybrid-section-title"><h5>المخرجات والتقارير المعتمدة</h5></div><div class="report-grid"><div class="empty-state">لا توجد مخرجات أو تقارير مسجلة.</div></div>');
  template.querySelector('.report-grid').insertAdjacentHTML('afterend',reportProposalAdd());
 }
 return `<section class="atwar-job-document"><div class="profile-job-viewer"><div class="profile-job-viewer-head"><div><h4>${esc(view.title)}</h4><p>${esc(view.subtitle)}</p></div></div><div class="profile-job-viewer-body">${template.innerHTML}${mode==='tasks'?'':add}</div></div></section>`;
}
function reportProposalAdd(){
 return managerReviewing()?'<button class="review-btn" data-propose="ADD" data-section="REPORTS" data-index="-1">إضافة مخرج أو تقرير مقترح</button>':'';
}
function responsibilitiesView(rows, limit = 0) {
  const visible = limit ? asArray(rows).slice(0, limit) : asArray(rows);
  return `<div class="responsibility-list">${visible.map((item,index) => `<article class="responsibility-item"><span class="number">${index + 1}</span><div><b>${esc(itemText(item))}</b>${proposalActions('RESPONSIBILITIES',index)}</div></article>`).join('') || '<div class="empty-state">لا توجد مهام مسجلة.</div>'}</div>${managerReviewing() && !limit ? '<button class="review-btn" data-propose="ADD" data-section="RESPONSIBILITIES" data-index="-1">إضافة مهمة مقترحة</button>' : ''}`;
}

function overviewView() {
  const content = job.content || {};
  const linked = assignments.filter(item => item.job_description_id === job.id);
  const linkedIds = new Set(linked.map(item => item.profile_id));
  const assignmentCard = canStage('ASSIGN') ? `<section class="content-card"><h2>ربط الوصف بالموظف</h2><p class="purpose-text">اختر الموظف ليظهر الوصف في ملفه الوظيفي. إذا كان الوصف قيد المراجعة فسيظهر له بعد الاعتماد والنشر.</p><div class="compose"><select id="assignmentEmployee"><option value="">اختر الموظف</option>${users.filter(user => !linkedIds.has(user.id)).map(user => `<option value="${user.id}">${esc(user.full_name)} — ${esc(user.job_title || user.email || '')}</option>`).join('')}</select><button id="assignEmployeeBtn" class="review-btn primary">ربط وإشعار الموظف</button></div><div class="comment-list">${linked.map(item => {const user=users.find(row=>row.id===item.profile_id);return `<div class="comment"><b>${esc(user?.full_name || item.profile_id)}</b><small>${job.published_snapshot ? 'النسخة السارية ظاهرة الآن في الملف الوظيفي' : 'سيظهر بعد الاعتماد والنشر'}</small></div>`}).join('') || '<div class="empty-state">لم يُربط هذا الوصف بموظف.</div>'}</div></section>` : '';
  return `<div class="content-stack">${lifecycleView()}${assignmentCard}${documentSection('description')}<div>${proposalActions('PURPOSE',-1)}</div><section class="mini-grid"><article class="mini-stat"><b>${asArray(content.responsibilities).length}</b><span>مهمة ومسؤولية</span></article><article class="mini-stat"><b>${asArray(content.authorities).length}</b><span>صلاحية وحد</span></article><article class="mini-stat"><b>${asArray(content.kpis).length}</b><span>مؤشر أداء</span></article><article class="mini-stat"><b>${asArray(content.reports).length + forms.length}</b><span>تقرير ونموذج</span></article></section><section class="content-card"><h2>أبرز المهام</h2>${responsibilitiesView(content.responsibilities,4)}</section></div>`;
}

function referenceWeightsView() {
  if (!weightReferences.length) return '';
  const total=weightReferences.reduce((sum,row)=>sum+Number(row.weight_percent),0);
  const draftNames=asArray(job.content?.kpis).map(itemText);
  const namesMatch=weightReferences.length===draftNames.length&&weightReferences.every((row,index)=>row.indicator_name===draftNames[index]);
  return `<section class="content-card scorecard-reference"><h2>أوزان بطاقة الأداء المرجعية</h2><p>الأوزان كما أرسلها صاحب النظام للوظيفة ${esc(job.title)}. إجماليها <b>${esc(total)}٪</b>. مرجع للمراجعة، ولا يغيّر المؤشرات في المسودة أو الوصف المنشور تلقائيًا.</p><div class="matrix-wrap"><table class="permission-matrix"><thead><tr><th scope="col">#</th><th scope="col">المؤشر في البطاقة المرجعية</th><th scope="col">الوزن</th></tr></thead><tbody>${weightReferences.map(row=>`<tr><td>${row.kpi_position}</td><td>${esc(row.indicator_name)}</td><td><b>${Number(row.weight_percent)}٪</b></td></tr>`).join('')}</tbody></table></div><p class="reference-note">${namesMatch?'أسماء وترتيب مؤشرات المسودة مطابقان لهذه البطاقة.':'أسماء أو ترتيب مؤشرات المسودة يختلف عن البطاقة المرجعية؛ يلزم توفيق المؤشرات في مسار المراجعة قبل الاعتماد.'} • مرجع الإصدار ${weightReferences[0].source_revision}.</p></section>`;
}


function measurementView() {
  const content = job.content || {};
  const reports = asArray(content.reports).map((item,index) => `<article class="metric-card"><b>${esc(itemText(item))}</b><p>${esc(item.recipient ? 'المستلم: ' + item.recipient : '')}</p><div class="metric-meta"><span>${esc(item.frequency || '')}</span><span>${esc(item.display_rule || 'داخل النظام')}</span></div>${proposalActions('REPORTS',index)}</article>`).join('');
  const formCards = forms.map(item => `<a class="form-link" href="${esc(item.file_url || '#')}" ${item.file_url ? 'target="_blank"' : ''}><b>${esc(item.title)}</b><span>${esc(item.form_type)} • الإصدار ${esc(item.version)}</span><small>${esc(item.usage_note || item.description || '')}</small></a>`).join('');
  return `<div class="content-stack">${referenceWeightsView()}${documentSection('performance')}<section class="content-card"><h2>التقارير والمخرجات</h2><div class="measurement-grid">${reports || '<div class="empty-state">لا توجد تقارير.</div>'}</div>${reportProposalAdd()}</section><section class="content-card"><h2>النماذج والأدلة المرتبطة</h2><div class="forms-list">${formCards || '<div class="empty-state">لم تُربط نماذج بهذه الوظيفة بعد.</div>'}</div></section></div>`;
}

function valueText(value) {
  return value == null ? '' : typeof value === 'string' ? value : (value.text || value.name || JSON.stringify(value));
}

function reviewView() {
  const comparisons = proposals.map(item => `<article class="comparison-card ${item.status}"><div class="comparison-head"><span class="tag">${{ADD:'إضافة',MODIFY:'تعديل',DELETE:'حذف',COMMENT:'ملاحظة'}[item.action]}</span><b>${sectionLabels[item.section] || item.section}${item.item_index !== null ? ` • البند ${item.item_index + 1}` : ''}</b><span class="tag">${{PENDING:'بانتظار القرار',ACCEPTED:'مقبول',REJECTED:'مرفوض',REVISED:'عُدل وقُبل'}[item.status]}</span></div><div class="compare-columns"><div><small>النص الحالي</small><p>${esc(valueText(item.original_value) || '—')}</p></div><div><small>اقتراح المدير</small><p>${esc(valueText(item.proposed_value) || '—')}</p></div></div><p><b>السبب:</b> ${esc(item.reason)}</p>${canStage('FINAL_REVIEW') && job.status === 'MANAGER_APPROVED' && !job.final_reviewed_at && item.status === 'PENDING' ? `<div class="item-actions"><button data-decision="ACCEPTED" data-proposal="${item.id}">قبول وتطبيق</button><button data-decision="REVISED" data-proposal="${item.id}">تعديل ثم قبول</button><button data-decision="REJECTED" data-proposal="${item.id}">رفض</button></div>` : ''}</article>`).join('');
  const commentRows = comments.map(item => `<div class="comment">${esc(item.body)}<small>${new Date(item.created_at).toLocaleString('ar-SA')}</small></div>`).join('');
  return `<div class="content-stack"><section class="content-card"><h2>مقترحات المدير</h2><p class="purpose-text">اقتراحات المدير لا تغيّر النسخة الرئيسية أو المنشورة؛ يراجع مسؤول النظام كل نقطة ويقرر قبولها أو تعديلها أو رفضها.</p><div class="comparison-list">${comparisons || '<div class="empty-state">لا توجد مقترحات.</div>'}</div></section><section class="content-card"><h2>ملاحظات المراجعة</h2><div class="comment-list">${commentRows || '<div class="empty-state">لا توجد ملاحظات.</div>'}</div><div class="compose"><input id="commentBody" placeholder="أضف ملاحظة واضحة"><button id="commentBtn" class="review-btn">إضافة</button></div></section></div>`;
}

function editView() {
  const content = job.content || {};
  if (activeTab === 'overview') return `<section class="content-card edit-grid"><div class="edit-field"><label>المسمى الوظيفي</label><input id="editTitle" value="${esc(job.title)}"></div><div class="edit-field"><label>العائلة الوظيفية</label><input id="editFamily" value="${esc(job.family || '')}"></div><div class="edit-field"><label>المستوى</label><input id="editLevel" value="${esc(job.job_level || '')}"></div><div class="edit-field"><label>المراجع المعتمد</label><select id="editReviewer" disabled><option value="">يتطلب تحديد مسؤول النظام</option>${users.map(user => `<option value="${user.id}" ${job.reviewer_id === user.id ? 'selected' : ''}>${esc(user.full_name)} — ${esc(user.role || '')}</option>`).join('')}</select></div><div class="edit-field" style="grid-column:1/-1"><label>الغرض الوظيفي</label><textarea id="editPurpose">${esc(job.purpose || '')}</textarea></div></section>`;
  const keys = activeTab === 'responsibilities' ? [['responsibilities','المهام والمسؤوليات']] : activeTab === 'authorities' ? [['authorities','الصلاحيات']] : [['kpis','مؤشرات الأداء'],['reports','التقارير والمخرجات']];
  return `<div class="content-stack">${keys.map(([key,title]) => `<section class="content-card"><h2>${title}</h2><div class="edit-list">${asArray(content[key]).map((item,index) => `<div class="edit-field"><label>البند ${index + 1}</label><textarea data-edit-list="${key}" data-index="${index}">${esc(itemText(item))}</textarea>${key==='kpis'&&Array.isArray(item.scale)?`<div class="hybrid-meta-grid">${item.scale.map((level,levelIndex)=>`<label>حد المستوى ${levelIndex+1}<input data-edit-scale="${index}" data-level-index="${levelIndex}" value="${esc(level.label||level.range||level.value||'')}"></label>`).join('')}<label>أساس التقييم<input data-edit-scale-basis="${index}" value="${esc(item.scale_basis||'')}"></label></div>`:''}</div>`).join('')}</div></section>`).join('')}</div>`;
}

function headerActions() {
  const buttons = [];
  if (canStage('DRAFT') && ['DRAFT','CHANGES_REQUESTED','PUBLISHED'].includes(job.status)) buttons.push(`<a href="create.html?id=${encodeURIComponent(job.id)}" class="review-btn">${job.status==='PUBLISHED'?'فتح مسودة إصدار جديد':'استكمال إعداد الوصف'}</a>`);
  if (canStage('FINAL_REVIEW') && job.status === 'MANAGER_APPROVED' && !job.final_reviewed_at) buttons.push(`<button id="editBtn" class="review-btn">${editing ? 'إلغاء التعديل' : 'تعديل المسودة'}</button>`);
  if (editing) buttons.push('<button id="saveBtn" class="review-btn primary">حفظ المسودة</button>');
  if (!editing && canStage('DRAFT') && ['DRAFT','CHANGES_REQUESTED'].includes(job.status)) buttons.push('<button id="submitBtn" class="review-btn primary">إرسال للمدير</button>');
  if (!editing && managerReviewing()) buttons.push(`<button id="managerDoneBtn" class="review-btn primary">${!me.manager_id?'إرسال لمدير النظام للاعتماد':'إنهاء المراجعة وإرسالها لمدير النظام'}</button>`);

  if (!editing && canStage('FINAL_REVIEW') && job.status === 'MANAGER_APPROVED' && !job.final_reviewed_at) buttons.push('<button id="finalReviewBtn" class="review-btn primary">إنهاء المراجعة النهائية</button>');
  if (!editing && canStage('PUBLISH') && job.status === 'MANAGER_APPROVED' && job.final_reviewed_at && !openSchedule()) buttons.push('<button id="publishBtn" class="review-btn primary">اعتماد وتحديد السريان</button>');
  if (!editing && !openSchedule() && ((job.status==='IN_REVIEW'&&job.reviewer_id===me.id)||(job.status==='MANAGER_APPROVED'&&(canStage('FINAL_REVIEW')||canStage('PUBLISH'))))) buttons.push('<button id="returnDraftBtn" class="review-btn">إعادة للتعديل</button>');
  if(!editing&&canStage('PUBLISH')&&job.status==='PUBLISHED')buttons.push('<button id="archiveJobBtn" class="review-btn">أرشفة الوصف</button>');
  return buttons.join('');
}

function render() {
  const reviewer = users.find(user => user.id === job.reviewer_id);
  const result = quality();
  byId('jobCode').textContent = job.job_code;
  byId('jobStatus').textContent = jobStage(job);
  byId('jobTitle').textContent = job.title;
  byId('jobPurpose').textContent = job.purpose || '';
  byId('jobFamily').textContent = job.family || 'غير محددة';
  byId('jobLevel').textContent = job.job_level || 'غير محدد';
  byId('jobRevision').textContent = job.revision;
  byId('jobReviewer').textContent = reviewer?.full_name || 'يتطلب تحديد مسؤول النظام';
  byId('proposalCount').textContent = proposals.filter(item => item.status === 'PENDING').length;
  byId('qualityScore').innerHTML = `<span>نسبة الاكتمال</span><b>${result.score}%</b>`;
  byId('qualityChecks').innerHTML = result.checks.map(([label,ok]) => `<div class="quality-check ${ok ? 'ok' : 'warn'}"><i data-lucide="${ok ? 'circle-check' : 'triangle-alert'}"></i>${label}</div>`).join('');
  const path=['إعداد الوصف','مراجعة المدير المباشر','المراجعة النهائية','الاعتماد والنشر','إقرار الموظف'];const position=job.status==='IN_REVIEW'?1:job.status==='MANAGER_APPROVED'?(job.final_reviewed_at?3:2):job.status==='PUBLISHED'?4:0;
  byId('workflowPath').innerHTML=path.map((label,i)=>`<li class="${i===position?'current':''}" ${i===position?'aria-current="step"':''}>${label}${i===position?' — المرحلة الحالية':''}</li>`).join('');
  const resolution = reviewerResolution();
  const ownerStage=position===0?'DRAFT':position===2?'FINAL_REVIEW':position===3?'PUBLISH':null;const ownerId=position===1?job.reviewer_id:stageOwners.find(x=>x.stage===ownerStage)?.profile_id;const owner=users.find(x=>x.id===ownerId)?.full_name;const pending=proposals.filter(x=>x.status==='PENDING'&&x.action!=='COMMENT').length;
  if(owner)resolution.text+=' المسؤول الحالي: '+owner+'.';
  if(position===2&&pending)resolution.text+=' يوجد '+pending+' مقترحات بانتظار القرار؛ راجع تبويب المقترحات قبل إنهاء المراجعة.';
  byId('managerAlert').className = `manager-alert ${resolution.state}`;
  byId('managerAlert').innerHTML = `<i data-lucide="${resolution.state === 'danger' ? 'triangle-alert' : 'network'}"></i><span>${esc(resolution.text)}</span>`;
  byId('headerActions').innerHTML = headerActions();
  document.querySelectorAll('[data-tab]').forEach(button => button.classList.toggle('active', button.dataset.tab === activeTab));
  byId('reviewBody').innerHTML = editing && activeTab !== 'review' ? editView() : activeTab === 'overview' ? overviewView() : activeTab === 'responsibilities' ? documentSection('tasks') : activeTab === 'authorities' ? documentSection('authority') : activeTab === 'measurement' ? measurementView() : activeTab==='history'?historyView():reviewView();
  bindActions();
  window.lucide?.createIcons();
}

function sourceItem(section,index) {
  if (section === 'PURPOSE') return job.purpose;
  const key = {RESPONSIBILITIES:'responsibilities',AUTHORITIES:'authorities',KPIS:'kpis',REPORTS:'reports'}[section];
  return index >= 0 ? asArray(job.content?.[key])[index] : null;
}

async function createProposal(section,index,action) {
  const original = sourceItem(section,index);
  let proposed = original;
  if (['MODIFY','ADD'].includes(action)) {
    const input = await window.AtwarUI.prompt({title:action === 'ADD' ? 'إضافة بند مقترح' : 'تعديل البند',message:action === 'ADD' ? 'اكتب البند الجديد المقترح.' : 'اكتب النص البديل المقترح.',value:action === 'ADD' ? '' : valueText(original),required:true});
    if (input === null || input.trim().length < 2) return;
    proposed = typeof original === 'object' ? {...original, [section === 'KPIS' || section === 'REPORTS' ? 'name' : 'text']:input.trim()} : input.trim();
  }
  const reason = await window.AtwarUI.prompt({title:action === 'COMMENT' ? 'إضافة ملاحظة' : 'سبب الاقتراح',message:'اكتب توضيحًا يساعد مسؤول النظام على اتخاذ القرار.',required:true});
  if (!reason || reason.trim().length < 2) return;
  const response = await sb.from('job_description_change_requests').insert({job_description_id:job.id,section,item_index:index >= 0 ? index : null,action,original_value:original,proposed_value:['DELETE','COMMENT'].includes(action) ? null : proposed,reason:reason.trim(),manager_id:me.id});
  if (response.error) return toast(response.error.message);
  await loadRelated();
  render();
  toast('حُفظ المقترح دون تغيير النسخة الرئيسية');
}

function applyProposal(record,value) {
  if (record.section === 'PURPOSE') return {purpose:valueText(value)};
  const key = {RESPONSIBILITIES:'responsibilities',AUTHORITIES:'authorities',KPIS:'kpis',REPORTS:'reports'}[record.section];
  const content = {...(job.content || {})};
  const rows = [...asArray(content[key])];
  if (record.action === 'ADD') rows.push(value);
  else if (record.action === 'DELETE') rows.splice(record.item_index,1);
  else rows[record.item_index] = value;
  content[key] = rows;
  return {content};
}

async function decideProposal(id,decision) {
  const record = proposals.find(item => item.id === id);
  if (!record) return;
  let value = record.proposed_value;
  if (decision === 'REVISED') {
    const input = await window.AtwarUI.prompt({title:'تعديل المقترح قبل اعتماده',value:valueText(value),required:true});
    if (input === null || input.trim().length < 2) return;
    value = typeof value === 'object' ? {...value,[record.section === 'KPIS' || record.section === 'REPORTS' ? 'name' : 'text']:input.trim()} : input.trim();
  }
  const note=decision==='REJECTED'?await window.AtwarUI.prompt({title:'سبب رفض المقترح',required:true}):null;
  if(decision==='REJECTED'&&note===null)return;
  const response=await sb.rpc('decide_job_description_proposal',{p_proposal_id:id,p_expected_revision:job.revision,p_decision:decision,p_value:value,p_note:note});
  if(response.error)return toast(response.error.message);
  job=response.data;
  await loadRelated();
  render();
  toast(decision === 'REJECTED' ? 'رُفض المقترح' : 'طُبق المقترح على المسودة');
}

function collectEdited(key) {
  const original = asArray(job.content?.[key]);
  return [...document.querySelectorAll(`[data-edit-list="${key}"]`)].map((node,index) => typeof original[index] === 'object' ? {...original[index],[key === 'responsibilities' || key === 'authorities' ? 'text' : 'name']:node.value.trim()} : node.value.trim()).filter(item => itemText(item));
}

async function saveDraft() {
  const payload = {updated_by:me.id};
  if (activeTab === 'overview') Object.assign(payload,{title:byId('editTitle').value.trim(),family:byId('editFamily').value.trim(),job_level:byId('editLevel').value.trim(),purpose:byId('editPurpose').value.trim(),reviewer_id:byId('editReviewer').value || null,status:job.status === 'PUBLISHED' ? 'DRAFT' : job.status});
  else {
    const content = {...(job.content || {})};
    if (activeTab === 'responsibilities') content.responsibilities = collectEdited('responsibilities');
    if (activeTab === 'authorities') content.authorities = collectEdited('authorities');
    if (activeTab === 'measurement') {content.kpis = collectEdited('kpis').map((item,index)=>({...item,...(Array.isArray(item.scale)?{scale:item.scale.map((level,levelIndex)=>({...level,label:document.querySelector(`[data-edit-scale="${index}"][data-level-index="${levelIndex}"]`)?.value.trim()||level.label})),scale_basis:document.querySelector(`[data-edit-scale-basis="${index}"]`)?.value.trim()||item.scale_basis}:{} )})); content.reports = collectEdited('reports');}
    payload.content = content;
    if (job.status === 'PUBLISHED') payload.status = 'DRAFT';
  }
  const response = await sb.from('job_descriptions').update(payload).eq('id',job.id).eq('revision',job.revision).select().maybeSingle();
  if (response.error || !response.data) return toast(response.error?.message || 'لم يسمح النظام بالحفظ');
  job = response.data;
  editing = false;
  render();
  toast('حُفظت المسودة وبقيت النسخة المنشورة للموظف دون تغيير');
}

async function transition(status) {
  if(status==='PUBLISHED'){
    if(activeTab!=='overview'){activeTab='overview';render();return toast('راجع تاريخ السريان ثم اضغط الاعتماد');}
    const date=byId('effectiveDate')?.value;if(!date||date<riyadhToday())return toast('حدد تاريخ السريان من اليوم أو بعده');
    const impact=await sb.rpc('get_job_publication_impact',{p_job_id:job.id,p_expected_revision:job.revision});
    if(impact.error)return toast(impact.error.message);
    const changes=publicationChanges(job),counts=impact.data;
    const message=[changes.firstPublication?'هذا أول إصدار معتمد للوصف.':`الإصدار المنشور الحالي: ${counts.published_revision}`,
      changes.changed.length?'الأجزاء المتغيرة: '+changes.changed.join('، '):'لا توجد تغييرات في محتوى الوصف مقارنة بالنسخة المنشورة.',
      `الموظفون المرتبطون: ${counts.linked_count}، منهم ${counts.active_count} حسابات نشطة و${counts.inactive_count} غير نشطة.`,
      `تاريخ السريان: ${byId('effectiveDate')?.value||riyadhToday()}. تصبح النسخة الجديدة متاحة وتُفتح مهام الإقرار عند بدء السريان، وتبقى النسخة الحالية متاحة حتى ذلك الوقت.`];
    if(!await window.AtwarUI.confirm({title:'مراجعة أثر الاعتماد والنشر',message:message.join('\n\n'),confirmText:'اعتماد الإصدار'}))return;
    const release=await sb.rpc('approve_job_effective_date',{p_job_id:job.id,p_expected_revision:job.revision,p_effective_date:byId('effectiveDate')?.value||riyadhToday()});
    if(release.error)return toast(release.error.message);job=release.data;await loadRelated();render();if(job.status==='PUBLISHED')void dispatchPublicationEmails();return toast(job.status==='PUBLISHED'?'اعتُمد الوصف وبدأ سريانه':'اعتُمد الوصف وحُفظ موعد السريان');
  }
  if(status==='IN_REVIEW'){const r=await sb.rpc('submit_job_description_draft',{p_job_id:job.id,p_expected_revision:job.revision});if(r.error)return toast(r.error.message);job=r.data;await loadRelated();render();return toast('أرسل الوصف إلى المدير المباشر للمراجعة');}
  if (status === 'MANAGER_APPROVED' && proposals.some(item => item.status === 'PENDING' && item.action !== 'COMMENT')) return toast('اتخذ قرارًا في جميع المقترحات أولًا');
  const payload = {status,updated_by:me.id};
  if (status === 'IN_REVIEW') payload.submitted_at = new Date().toISOString();
  const response = await sb.from('job_descriptions').update(payload).eq('id',job.id).eq('revision',job.revision).select().maybeSingle();
  if (response.error || !response.data) return toast(response.error?.message || 'تعذر تغيير حالة الوصف');
  job = response.data;
  if(status==='PUBLISHED')void dispatchPublicationEmails();
  render();
  toast(status === 'PUBLISHED' ? 'اعتُمد الوصف ونُشرت نسخة الموظف' : 'تم تحديث مسار المراجعة');
}

async function managerDone() {
  const response = await sb.rpc('complete_job_description_review',{p_job_id:job.id});
  if (response.error) return toast(response.error.message);
  job = response.data;
  await loadRelated();
  activeTab = 'review';
  render();
  toast('تم الإرسال إلى مدير النظام للمراجعة والاعتماد');
}

async function finishFinalReview() {
  const latest = await sb.from('job_description_change_requests').select('*').eq('job_description_id',job.id).order('created_at');
  if (latest.error) return toast('تعذر التحقق من المقترحات. حاول مرة أخرى قبل إنهاء المراجعة.');
  proposals = latest.data || [];
  const pending = proposals.filter(item => item.status === 'PENDING' && item.action !== 'COMMENT');
  if (pending.length) {
    editing = false;
    activeTab = 'review';
    render();
    return toast(`يوجد ${pending.length} مقترحات بانتظار القرار. اقبلها أو عدّلها أو ارفضها قبل إنهاء المراجعة.`);
  }
  const result = await sb.rpc('finish_job_final_review',{p_job_id:job.id});
  if (result.error) {
    if (result.error.message?.includes('Resolve pending proposals first')) {
      editing = false;
      activeTab = 'review';
      await loadRelated();
      render();
      return toast('أضيفت مقترحات جديدة بانتظار القرار. راجعها قبل إنهاء المراجعة.');
    }
    return toast(result.error.message);
  }
  job = result.data;
  render();
  toast('اكتملت المراجعة النهائية وانتقلت المهمة لمسؤول النشر');
}

async function assignEmployee() {
  const profileId = byId('assignmentEmployee')?.value;
  if (!profileId) return toast('اختر الموظف أولًا');
  const response = await sb.from('employee_job_assignments').upsert({profile_id:profileId,job_description_id:job.id,assigned_by:me.id,updated_by:me.id},{onConflict:'profile_id'});
  if (response.error) return toast(response.error.message);
  await loadRelated();
  if(job.status==='PUBLISHED')void dispatchPublicationEmails();
  render();
  toast(job.status === 'PUBLISHED' ? 'تم الربط وإشعار الموظف' : 'تم الربط؛ سيظهر الوصف للموظف بعد النشر');
}

async function dispatchPublicationEmails(){
  try{
    const {data,error}=await sb.functions.invoke('send-job-publication-notifications',{body:{}});
    if(error||data?.failed)console.warn('Publication emails pending retry:',data?.error||error?.message||data);
  }catch(error){console.warn('Publication emails pending retry:',error)}
}

async function addComment() {
  const body = byId('commentBody')?.value.trim();
  if (!body || body.length < 2) return;
  const response = await sb.from('job_description_comments').insert({job_description_id:job.id,author_id:me.id,body});
  if (response.error) return toast(response.error.message);
  await loadRelated();
  render();
}

function bindActions() {
  document.querySelectorAll('[data-propose]').forEach(button => button.onclick = () => createProposal(button.dataset.section,Number(button.dataset.index),button.dataset.propose));
  document.querySelectorAll('[data-decision]').forEach(button => button.onclick = () => decideProposal(button.dataset.proposal,button.dataset.decision));
  byId('editBtn')?.addEventListener('click',() => {
    editing = !editing;
    if (editing && activeTab === 'review') activeTab = 'responsibilities';
    render();
  });
  byId('saveBtn')?.addEventListener('click',saveDraft);
  byId('submitBtn')?.addEventListener('click',() => transition('IN_REVIEW'));
  byId('managerDoneBtn')?.addEventListener('click',managerDone);
  byId('adminDoneBtn')?.addEventListener('click',() => transition('MANAGER_APPROVED'));
  byId('archiveJobBtn')?.addEventListener('click',async()=>{if(await window.AtwarUI.confirm({title:'أرشفة الوصف الوظيفي',message:'لن يُستخدم الوصف للإسناد الجديد. تبقى النسخ السابقة محفوظة.'}))await transition('ARCHIVED');});
  byId('returnDraftBtn')?.addEventListener('click',returnForChanges);
  byId('finalReviewBtn')?.addEventListener('click',finishFinalReview);
  byId('publishBtn')?.addEventListener('click',() => transition('PUBLISHED'));
  for(const id of ['periodicOwner','periodicDue','periodicInterval','periodicEnabled'])byId(id)?.addEventListener('change',()=>{lifecycleDirty=true;});
  byId('effectiveDate')?.addEventListener('change',e=>{effectiveChoice=e.target.value;});
  byId('cancelEffectiveDate')?.addEventListener('click',cancelEffectiveDate);
  byId('savePeriodicReview')?.addEventListener('click',savePeriodicReview);
  byId('requestPeriodicChange')?.addEventListener('click',requestPeriodicChange);
  byId('completePeriodicReview')?.addEventListener('click',completePeriodicReview);
  byId('commentBtn')?.addEventListener('click',addComment);
  byId('assignEmployeeBtn')?.addEventListener('click',assignEmployee);
}

async function loadRelated() {
  const responses = await Promise.all([
    sb.from('job_description_change_requests').select('*').eq('job_description_id',job.id).order('created_at'),
    sb.from('job_description_forms').select('usage_note,display_order,form_library(*)').eq('job_description_id',job.id).order('display_order'),
    sb.from('job_description_comments').select('*').eq('job_description_id',job.id).order('created_at'),
    canStage('ASSIGN') ? sb.from('employee_job_assignments').select('*') : Promise.resolve({data:[]}),
    sb.from('job_description_versions').select('revision,action,snapshot,actor_id,change_note,created_at').eq('job_description_id',job.id).order('revision',{ascending:false}).limit(30),
    sb.from('job_scorecard_weight_references').select('source_revision,kpi_position,indicator_name,weight_percent').eq('job_description_id',job.id).order('source_revision',{ascending:false}).order('kpi_position'),
    sb.from('job_publication_schedules').select('*').eq('job_description_id',job.id).order('approved_at',{ascending:false}),
    sb.from('job_periodic_reviews').select('*').eq('job_description_id',job.id).maybeSingle(),
    sb.from('job_periodic_review_events').select('*').eq('job_description_id',job.id).order('reviewed_at',{ascending:false}).limit(20)
  ]);
  for(const response of responses.slice(6))if(response.error)throw response.error;
  schedules=responses[6].data||[];periodicReview=responses[7].data||null;periodicEvents=responses[8].data||[];
  const scheduled=openSchedule();job.scheduled_effective_date=scheduled?.effective_date;job.schedule_status=scheduled?.status;
  proposals = responses[0].data || [];
  forms = (responses[1].data || []).map(item => ({...item.form_library,usage_note:item.usage_note}));
  comments = responses[2].data || [];
  assignments = responses[3].data || [];
  if (responses[4].error) throw responses[4].error;
  versions=responses[4].data||[];
  if (responses[5].error) throw responses[5].error;
  weightReferences = (responses[5].data || []).filter(row => row.source_revision === responses[5].data?.[0]?.source_revision);
}

async function boot() {
  ({data:{session}} = await sb.auth.getSession());
  if (!session?.user) return location.href = '../login.html';
  const profile = await sb.from('profiles').select('id,full_name,email,role,job_title,department,manager_id,active,status').eq('id',session.user.id).single();
  me = profile.data;
  if (!me) return location.href = '../profile/job-description.html';
  window.atwarSyncShellIdentity?.(me,session.user);
  const stages=await sb.from('job_stage_owners').select('stage,profile_id');if(stages.error)throw stages.error;stageOwners=stages.data||[];stagePermissions=new Set((stages.data||[]).filter(x=>x.profile_id===me.id).map(x=>x.stage));
  if(canStage('DRAFT')||canStage('ASSIGN')||canStage('FINAL_REVIEW')){const directory=await sb.rpc('job_stage_directory');if(directory.error)throw directory.error;users=directory.data||[]}else users=[me];
  const id = new URLSearchParams(location.search).get('id');
  if (!id) throw new Error('لم يتم تحديد الوظيفة المطلوبة');
  const response = await sb.from('job_descriptions').select('*').eq('id',id).maybeSingle();
  if (response.error || !response.data) throw new Error(response.error?.message || 'الوصف غير موجود أو غير متاح');
  job = response.data;
  if (!canStage('DRAFT')&&!canStage('ASSIGN')&&!canStage('FINAL_REVIEW')&&!canStage('PUBLISH')&&job.reviewer_id !== me.id) return location.href = '../profile/job-description.html';
  await loadRelated();
  byId('reviewState').hidden = true;
  byId('reviewApp').hidden = false;
  document.body.style.visibility = 'visible';
  render();
  if(canStage('PUBLISH'))void dispatchPublicationEmails();
}

async function returnForChanges(){const reason=await window.AtwarUI.prompt({title:'إعادة الوصف للتعديل',message:'حدد المطلوب تصحيحه؛ يُحفظ السبب وتُفتح مهمة للإعداد.',required:true});if(reason===null)return;const r=await sb.rpc('return_job_description_for_changes',{p_job_id:job.id,p_expected_revision:job.revision,p_reason:reason});if(r.error)return toast(r.error.message);job=r.data;editing=false;await loadRelated();render();toast('أعيد الوصف للتعديل وسُجل السبب');}

function versionHistoryView(){const previous=job.published_snapshot;const fields=[['المسمى',previous?.title,job.title],['الغرض',previous?.purpose,job.purpose],...['responsibilities','authorities','kpis','reports','qualifications','relationships'].map(key=>[{responsibilities:'المهام والمسؤوليات',authorities:'الصلاحيات',kpis:'المؤشرات',reports:'المخرجات',qualifications:'المؤهلات',relationships:'العلاقات'}[key],previous?.content?.[key],job.content?.[key]])];const text=value=>typeof value==='object'?JSON.stringify(value,null,2):value||'—';return `<section class="content-card"><h2>مقارنة المسودة بالنسخة المنشورة</h2>${previous?fields.filter(([,a,b])=>JSON.stringify(a)!==JSON.stringify(b)).map(([label,a,b])=>`<article class="comparison-card"><h3>${esc(label)}</h3><div class="compare-columns"><div><small>النسخة المنشورة ${esc(previous.revision)}</small><p style="white-space:pre-wrap">${esc(text(a))}</p></div><div><small>المسودة الحالية</small><p style="white-space:pre-wrap">${esc(text(b))}</p></div></div></article>`).join('')||'<p>لا توجد تغييرات عن المحتوى المنشور.</p>':'<p>لم يُنشر إصدار سابق لهذا الوصف.</p>'}</section><section class="content-card"><h2>سجل الإصدارات والقرارات</h2><div style="overflow:auto"><table class="workflow-history"><thead><tr><th>الإصدار</th><th>الإجراء</th><th>المسؤول</th><th>التاريخ</th><th>السبب</th></tr></thead><tbody>${versions.map(v=>`<tr><td>${v.revision}</td><td>${esc({CREATED:'إنشاء',UPDATED:'تحديث',SUBMITTED:'إرسال للمراجعة',CHANGES_REQUESTED:'إعادة للتعديل',MANAGER_APPROVED:'إنهاء مراجعة المدير',PUBLISHED:'اعتماد ونشر',ARCHIVED:'أرشفة'}[v.action]||v.action)}</td><td>${esc(users.find(u=>u.id===v.actor_id)?.full_name||'المسؤول المسجل')}</td><td>${new Date(v.created_at).toLocaleString('ar-SA')}</td><td>${esc(v.change_note||'—')}</td></tr>`).join('')}</tbody></table></div></section>`;}

document.querySelectorAll('[data-tab]').forEach(button => button.onclick = () => {activeTab = button.dataset.tab; editing = false; render();});
boot().catch(error => {
  console.error(error);
  document.body.style.visibility = 'visible';
  byId('reviewState').textContent = 'تعذر فتح المراجعة: ' + error.message;
});

function openSchedule(){return schedules.find(s=>['PENDING','BLOCKED'].includes(s.status));}

function lifecycleView(){return renderJobLifecycle({job,scheduled:openSchedule(),periodicReview,periodicEvents,users,stageOwners,me,canStage,today:riyadhToday(),effectiveChoice});}

async function cancelEffectiveDate(){
 const s=openSchedule(),note=await window.AtwarUI.prompt({title:'إلغاء جدولة السريان',message:'يسجل السبب ويعود الوصف إلى بانتظار الاعتماد. النسخة السارية تبقى متاحة.',required:true});if(note===null)return;
 const r=await sb.rpc('cancel_job_effective_date',{p_schedule_id:s.id,p_note:note});if(r.error)return toast(r.error.message);await loadRelated();render();toast('ألغيت الجدولة وسُجل السبب');
}
async function savePeriodicReview(){
 const r=await sb.rpc('save_job_periodic_review',{p_job_id:job.id,p_expected_revision:periodicReview?.revision||0,p_reviewer_id:byId('periodicOwner')?.value,p_due_on:byId('periodicDue')?.value,p_interval_months:Number(byId('periodicInterval')?.value),p_enabled:byId('periodicEnabled')?.value==='true'});
 if(r.error)return toast(r.error.message);lifecycleDirty=false;await loadRelated();render();toast('حُفظ إعداد المراجعة الدورية');
}
async function completePeriodicReview(){
 const note=await window.AtwarUI.prompt({title:'خلاصة المراجعة الدورية',message:'أكد أن النسخة السارية مناسبة ولم تستلزم تعديلًا.',value:'تمت المراجعة ولا توجد تغييرات.',required:true});if(note===null)return;
 const r=await sb.rpc('complete_job_periodic_review',{p_job_id:job.id,p_expected_revision:periodicReview.revision,p_published_revision:Number(job.published_snapshot.revision),p_note:note});if(r.error)return toast(r.error.message);await loadRelated();render();toast('سُجلت المراجعة وحدد موعدها التالي دون تغيير الإصدار');
}

async function refreshLifecycle(){
 if(!job||editing||lifecycleDirty||refreshingLifecycle||document.visibilityState==='hidden'||document.activeElement?.matches('input,select,textarea'))return;
 refreshingLifecycle=true;try{const r=await sb.from('job_descriptions').select('*').eq('id',job.id).maybeSingle();if(r.error||!r.data)return;job=r.data;await loadRelated();render();}catch(error){console.warn('تعذر تحديث حالة دورة الوصف',error.message);}finally{refreshingLifecycle=false;}
}
setInterval(refreshLifecycle,60000);
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')void refreshLifecycle();});
window.addEventListener('beforeunload',e=>{if(lifecycleDirty){e.preventDefault();e.returnValue='';}});

async function requestPeriodicChange(){
 const note=await window.AtwarUI.prompt({title:'طلب تحديث الوصف بعد المراجعة الدورية',message:'وضح التعديلات المطلوبة. يُحفظ الطلب وتُفتح مهمة لمسؤول إعداد الأوصاف، وتبقى النسخة السارية دون تغيير.',required:true});if(note===null)return;
 const r=await sb.rpc('request_job_periodic_change',{p_job_id:job.id,p_expected_revision:periodicReview.revision,p_published_revision:Number(job.published_snapshot.revision),p_note:note});if(r.error)return toast(r.error.message);await loadRelated();render();toast('حُفظ طلب التحديث وفتحت مهمة لمسؤول الإعداد');
}

function historyView(){const labels={PENDING:'معتمد بانتظار السريان',PUBLISHED:'بدأ السريان',CANCELLED:'ألغيت الجدولة',BLOCKED:'تعذر بدء السريان'};return versionHistoryView()+`<section class="content-card"><h2>سجل السريان والجدولة</h2><div class="comment-list">${schedules.map(s=>`<div class="comment"><b>${esc(labels[s.status])} — السريان ${esc(s.effective_date)}</b><small>اعتمد في ${new Date(s.approved_at).toLocaleString('ar-SA')} • ${esc(users.find(u=>u.id===s.approved_by)?.full_name||'المعتمد المسجل')}</small>${s.note?`<p>${esc(s.note)}</p>`:''}</div>`).join('')||'<p>لا توجد قرارات سريان مجدولة مسجلة لهذا الوصف.</p>'}</div></section>`;}
