const sb = await window.atwarGetSupabase();
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const byId = id => document.getElementById(id);
const asArray = value => Array.isArray(value) ? value : [];
const itemText = value => typeof value === 'string' ? value : (value?.text || value?.name || '');
const statusLabels = {DRAFT:'مسودة',IN_REVIEW:'قيد المراجعة',CHANGES_REQUESTED:'تحتاج تعديل',MANAGER_APPROVED:'موافقة المدير مكتملة',PUBLISHED:'منشورة',ARCHIVED:'مؤرشفة'};
const sectionLabels = {PURPOSE:'الغرض الوظيفي',RESPONSIBILITIES:'المهام والمسؤوليات',AUTHORITIES:'الصلاحيات',KPIS:'مؤشرات الأداء',REPORTS:'التقارير والمخرجات',QUALIFICATIONS:'المؤهلات'};
let session, me, job, users = [], assignments = [], proposals = [], forms = [], comments = [], activeTab = 'overview', editing = false;

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
  return me.role !== 'admin' && job.reviewer_id === me.id && ['IN_REVIEW','CHANGES_REQUESTED'].includes(job.status);
}

function quality() {
  const content = job.content || {};
  const checks = [
    ['الغرض الوظيفي', (job.purpose || '').trim().length >= 40],
    ['8 مهام ومسؤوليات على الأقل', asArray(content.responsibilities).length >= 8],
    ['مصفوفة صلاحيات واضحة', asArray(content.authorities).length >= 4],
    ['4 مؤشرات أداء على الأقل', asArray(content.kpis).length >= 4],
    ['تقارير ومخرجات محددة', asArray(content.reports).length >= 2],
    ['مؤهلات الوظيفة', Boolean(content.qualifications?.education)]
  ];
  return {checks, score: Math.round(checks.filter(item => item[1]).length / checks.length * 100)};
}

function reviewerResolution() {
  if (me.role !== 'admin') {
    return job.reviewer_id === me.id
      ? {state:'', text:'أنت المدير المباشر المكلّف بمراجعة هذه الوظيفة، ويمكنك اقتراح تعديل أو حذف أو إضافة دون تغيير النسخة الرئيسية.'}
      : {state:'danger', text:'هذه الوظيفة ليست ضمن نطاق مراجعتك الحالي.'};
  }
  const linked = assignments.filter(item => item.job_description_id === job.id);
  const linkedUsers = linked.map(item => users.find(user => user.id === item.profile_id)).filter(Boolean);
  const managerIds = [...new Set(linkedUsers.map(user => user.manager_id).filter(Boolean))];
  const missing = linkedUsers.filter(user => !user.manager_id);
  if (!linkedUsers.length) return {state:'warning', text:'لم تُربط الوظيفة بموظف حتى الآن. يحدد مسؤول النظام المدير عند أول استخدام.'};
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

function responsibilitiesView(rows, limit = 0) {
  const visible = limit ? asArray(rows).slice(0, limit) : asArray(rows);
  return `<div class="responsibility-list">${visible.map((item,index) => `<article class="responsibility-item"><span class="number">${index + 1}</span><div><b>${esc(itemText(item))}</b>${proposalActions('RESPONSIBILITIES',index)}</div></article>`).join('') || '<div class="empty-state">لا توجد مهام مسجلة.</div>'}</div>${managerReviewing() && !limit ? '<button class="review-btn" data-propose="ADD" data-section="RESPONSIBILITIES" data-index="-1">إضافة مهمة مقترحة</button>' : ''}`;
}

function overviewView() {
  const content = job.content || {};
  const linked = assignments.filter(item => item.job_description_id === job.id);
  const linkedIds = new Set(linked.map(item => item.profile_id));
  const assignmentCard = me.role === 'admin' ? `<section class="content-card"><h2>ربط الوصف بالموظف</h2><p class="purpose-text">اختر الموظف ليظهر الوصف في ملفه الوظيفي. إذا كان الوصف قيد المراجعة فسيظهر له بعد الاعتماد والنشر.</p><div class="compose"><select id="assignmentEmployee"><option value="">اختر الموظف</option>${users.filter(user => !linkedIds.has(user.id)).map(user => `<option value="${user.id}">${esc(user.full_name)} — ${esc(user.job_title || user.email || '')}</option>`).join('')}</select><button id="assignEmployeeBtn" class="review-btn primary">ربط وإشعار الموظف</button></div><div class="comment-list">${linked.map(item => {const user=users.find(row=>row.id===item.profile_id);return `<div class="comment"><b>${esc(user?.full_name || item.profile_id)}</b><small>${job.status === 'PUBLISHED' ? 'الوصف ظاهر الآن في الملف الوظيفي' : 'سيظهر بعد الاعتماد والنشر'}</small></div>`}).join('') || '<div class="empty-state">لم يُربط هذا الوصف بموظف.</div>'}</div></section>` : '';
  return `<div class="content-stack">${assignmentCard}<section class="content-card"><h2>الغرض الوظيفي</h2><div class="purpose-text">${esc(job.purpose || 'غير محدد')}</div>${proposalActions('PURPOSE',-1)}</section><section class="mini-grid"><article class="mini-stat"><b>${asArray(content.responsibilities).length}</b><span>مهمة ومسؤولية</span></article><article class="mini-stat"><b>${asArray(content.authorities).length}</b><span>صلاحية وحد</span></article><article class="mini-stat"><b>${asArray(content.kpis).length}</b><span>مؤشر أداء</span></article><article class="mini-stat"><b>${asArray(content.reports).length + forms.length}</b><span>تقرير ونموذج</span></article></section><section class="content-card"><h2>أبرز المهام</h2>${responsibilitiesView(content.responsibilities,4)}</section></div>`;
}

function authoritiesView() {
  const rows = asArray(job.content?.authorities);
  return `<section class="content-card"><h2>مصفوفة الصلاحيات</h2><div class="matrix-wrap"><table class="permission-matrix"><thead><tr><th>الإجراء</th><th>مستوى الصلاحية</th><th>النطاق والحد</th><th>التصعيد</th></tr></thead><tbody>${rows.map((item,index) => `<tr><td><b>${esc(itemText(item))}</b>${proposalActions('AUTHORITIES',index)}</td><td class="type">${esc(item.type || 'تنفيذ')}</td><td>${esc([item.scope,item.limit].filter(Boolean).join(' — ') || 'وفق التفويض المعتمد')}</td><td>${esc(item.escalation || 'المدير المباشر')}</td></tr>`).join('')}</tbody></table></div>${managerReviewing() ? '<button class="review-btn" data-propose="ADD" data-section="AUTHORITIES" data-index="-1">إضافة صلاحية مقترحة</button>' : ''}</section>`;
}

function measurementView() {
  const content = job.content || {};
  const metrics = asArray(content.kpis).map((item,index) => `<article class="metric-card"><b>${esc(itemText(item))}</b><p>${esc(item.measure || '')}</p><div class="metric-meta"><span>المستهدف: ${esc(item.target || 'يحدد')}</span><span>${esc(item.frequency || '')}</span></div>${proposalActions('KPIS',index)}</article>`).join('');
  const reports = asArray(content.reports).map((item,index) => `<article class="metric-card"><b>${esc(itemText(item))}</b><p>${esc(item.recipient ? 'المستلم: ' + item.recipient : '')}</p><div class="metric-meta"><span>${esc(item.frequency || '')}</span><span>${esc(item.display_rule || 'داخل النظام')}</span></div>${proposalActions('REPORTS',index)}</article>`).join('');
  const formCards = forms.map(item => `<a class="form-link" href="${esc(item.file_url || '#')}" ${item.file_url ? 'target="_blank"' : ''}><b>${esc(item.title)}</b><span>${esc(item.form_type)} • الإصدار ${esc(item.version)}</span><small>${esc(item.usage_note || item.description || '')}</small></a>`).join('');
  return `<div class="content-stack"><section class="content-card"><h2>مؤشرات الأداء</h2><div class="measurement-grid">${metrics || '<div class="empty-state">لا توجد مؤشرات.</div>'}</div></section><section class="content-card"><h2>التقارير والمخرجات</h2><div class="measurement-grid">${reports || '<div class="empty-state">لا توجد تقارير.</div>'}</div></section><section class="content-card"><h2>النماذج والأدلة المرتبطة</h2><div class="forms-list">${formCards || '<div class="empty-state">لم تُربط نماذج بهذه الوظيفة بعد.</div>'}</div></section></div>`;
}

function valueText(value) {
  return value == null ? '' : typeof value === 'string' ? value : (value.text || value.name || JSON.stringify(value));
}

function reviewView() {
  const comparisons = proposals.map(item => `<article class="comparison-card ${item.status}"><div class="comparison-head"><span class="tag">${{ADD:'إضافة',MODIFY:'تعديل',DELETE:'حذف',COMMENT:'ملاحظة'}[item.action]}</span><b>${sectionLabels[item.section] || item.section}${item.item_index !== null ? ` • البند ${item.item_index + 1}` : ''}</b><span class="tag">${{PENDING:'بانتظار القرار',ACCEPTED:'مقبول',REJECTED:'مرفوض',REVISED:'عُدل وقُبل'}[item.status]}</span></div><div class="compare-columns"><div><small>النص الحالي</small><p>${esc(valueText(item.original_value) || '—')}</p></div><div><small>اقتراح المدير</small><p>${esc(valueText(item.proposed_value) || '—')}</p></div></div><p><b>السبب:</b> ${esc(item.reason)}</p>${me.role === 'admin' && item.status === 'PENDING' ? `<div class="item-actions"><button data-decision="ACCEPTED" data-proposal="${item.id}">قبول وتطبيق</button><button data-decision="REVISED" data-proposal="${item.id}">تعديل ثم قبول</button><button data-decision="REJECTED" data-proposal="${item.id}">رفض</button></div>` : ''}</article>`).join('');
  const commentRows = comments.map(item => `<div class="comment">${esc(item.body)}<small>${new Date(item.created_at).toLocaleString('ar-SA')}</small></div>`).join('');
  return `<div class="content-stack"><section class="content-card"><h2>مقترحات المدير</h2><p class="purpose-text">اقتراحات المدير لا تغيّر النسخة الرئيسية أو المنشورة؛ يراجع مسؤول النظام كل نقطة ويقرر قبولها أو تعديلها أو رفضها.</p><div class="comparison-list">${comparisons || '<div class="empty-state">لا توجد مقترحات.</div>'}</div></section><section class="content-card"><h2>ملاحظات المراجعة</h2><div class="comment-list">${commentRows || '<div class="empty-state">لا توجد ملاحظات.</div>'}</div><div class="compose"><input id="commentBody" placeholder="أضف ملاحظة واضحة"><button id="commentBtn" class="review-btn">إضافة</button></div></section></div>`;
}

function editView() {
  const content = job.content || {};
  if (activeTab === 'overview') return `<section class="content-card edit-grid"><div class="edit-field"><label>المسمى الوظيفي</label><input id="editTitle" value="${esc(job.title)}"></div><div class="edit-field"><label>العائلة الوظيفية</label><input id="editFamily" value="${esc(job.family || '')}"></div><div class="edit-field"><label>المستوى</label><input id="editLevel" value="${esc(job.job_level || '')}"></div><div class="edit-field"><label>المراجع المعتمد</label><select id="editReviewer"><option value="">يتطلب تحديد مسؤول النظام</option>${users.map(user => `<option value="${user.id}" ${job.reviewer_id === user.id ? 'selected' : ''}>${esc(user.full_name)} — ${esc(user.role || '')}</option>`).join('')}</select></div><div class="edit-field" style="grid-column:1/-1"><label>الغرض الوظيفي</label><textarea id="editPurpose">${esc(job.purpose || '')}</textarea></div></section>`;
  const keys = activeTab === 'responsibilities' ? [['responsibilities','المهام والمسؤوليات']] : activeTab === 'authorities' ? [['authorities','الصلاحيات']] : [['kpis','مؤشرات الأداء'],['reports','التقارير والمخرجات']];
  return `<div class="content-stack">${keys.map(([key,title]) => `<section class="content-card"><h2>${title}</h2><div class="edit-list">${asArray(content[key]).map((item,index) => `<div class="edit-field"><label>البند ${index + 1}</label><textarea data-edit-list="${key}" data-index="${index}">${esc(itemText(item))}</textarea></div>`).join('')}</div></section>`).join('')}</div>`;
}

function headerActions() {
  const buttons = [];
  if (me.role === 'admin') buttons.push(`<button id="editBtn" class="review-btn">${editing ? 'إلغاء التعديل' : 'تعديل المسودة'}</button>`);
  if (editing) buttons.push('<button id="saveBtn" class="review-btn primary">حفظ المسودة</button>');
  if (!editing && me.role === 'admin' && ['DRAFT','CHANGES_REQUESTED','PUBLISHED'].includes(job.status)) buttons.push('<button id="submitBtn" class="review-btn primary">إرسال للمدير</button>');
  if (!editing && managerReviewing()) buttons.push('<button id="managerDoneBtn" class="review-btn primary">إنهاء مراجعة المدير</button>');
  if (!editing && me.role === 'admin' && job.status === 'IN_REVIEW') buttons.push('<button id="adminDoneBtn" class="review-btn primary">إنهاء مراجعة المقترحات</button>');
  if (!editing && me.role === 'admin' && job.status === 'MANAGER_APPROVED') buttons.push('<button id="publishBtn" class="review-btn primary">اعتماد ونشر</button>');
  return buttons.join('');
}

function render() {
  const reviewer = users.find(user => user.id === job.reviewer_id);
  const result = quality();
  byId('jobCode').textContent = job.job_code;
  byId('jobStatus').textContent = statusLabels[job.status] || job.status;
  byId('jobTitle').textContent = job.title;
  byId('jobPurpose').textContent = job.purpose || '';
  byId('jobFamily').textContent = job.family || 'غير محددة';
  byId('jobLevel').textContent = job.job_level || 'غير محدد';
  byId('jobRevision').textContent = job.revision;
  byId('jobReviewer').textContent = reviewer?.full_name || 'يتطلب تحديد مسؤول النظام';
  byId('proposalCount').textContent = proposals.filter(item => item.status === 'PENDING').length;
  byId('qualityScore').innerHTML = `<span>نسبة الاكتمال</span><b>${result.score}%</b>`;
  byId('qualityChecks').innerHTML = result.checks.map(([label,ok]) => `<div class="quality-check ${ok ? 'ok' : 'warn'}"><i data-lucide="${ok ? 'circle-check' : 'triangle-alert'}"></i>${label}</div>`).join('');
  const resolution = reviewerResolution();
  byId('managerAlert').className = `manager-alert ${resolution.state}`;
  byId('managerAlert').innerHTML = `<i data-lucide="${resolution.state === 'danger' ? 'triangle-alert' : 'network'}"></i><span>${esc(resolution.text)}</span>`;
  byId('headerActions').innerHTML = headerActions();
  document.querySelectorAll('[data-tab]').forEach(button => button.classList.toggle('active', button.dataset.tab === activeTab));
  byId('reviewBody').innerHTML = editing && activeTab !== 'review' ? editView() : activeTab === 'overview' ? overviewView() : activeTab === 'responsibilities' ? `<section class="content-card"><h2>المهام والمسؤوليات</h2>${responsibilitiesView(job.content?.responsibilities)}</section>` : activeTab === 'authorities' ? authoritiesView() : activeTab === 'measurement' ? measurementView() : reviewView();
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
    const input = prompt(action === 'ADD' ? 'اكتب البند المقترح:' : 'اكتب النص البديل:', action === 'ADD' ? '' : valueText(original));
    if (input === null || input.trim().length < 2) return;
    proposed = typeof original === 'object' ? {...original, [section === 'KPIS' || section === 'REPORTS' ? 'name' : 'text']:input.trim()} : input.trim();
  }
  const reason = prompt(action === 'COMMENT' ? 'اكتب الملاحظة:' : 'اكتب سبب الاقتراح:', '');
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
    const input = prompt('عدّل النص المقترح قبل اعتماده:', valueText(value));
    if (input === null || input.trim().length < 2) return;
    value = typeof value === 'object' ? {...value,[record.section === 'KPIS' || record.section === 'REPORTS' ? 'name' : 'text']:input.trim()} : input.trim();
  }
  if (decision !== 'REJECTED' && record.action !== 'COMMENT') {
    const update = await sb.from('job_descriptions').update({...applyProposal(record,value),updated_by:me.id}).eq('id',job.id).select().maybeSingle();
    if (update.error || !update.data) return toast(update.error?.message || 'تعذر تطبيق المقترح');
    job = update.data;
  }
  const note = decision === 'REJECTED' ? (prompt('سبب الرفض:','') || 'لم يعتمد') : null;
  const response = await sb.from('job_description_change_requests').update({status:decision,proposed_value:value,admin_note:note}).eq('id',id);
  if (response.error) return toast(response.error.message);
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
    if (activeTab === 'measurement') {content.kpis = collectEdited('kpis'); content.reports = collectEdited('reports');}
    payload.content = content;
    if (job.status === 'PUBLISHED') payload.status = 'DRAFT';
  }
  const response = await sb.from('job_descriptions').update(payload).eq('id',job.id).select().maybeSingle();
  if (response.error || !response.data) return toast(response.error?.message || 'لم يسمح النظام بالحفظ');
  job = response.data;
  editing = false;
  render();
  toast('حُفظت المسودة وبقيت النسخة المنشورة للموظف دون تغيير');
}

async function transition(status) {
  if (status === 'IN_REVIEW') {
    const resolution = reviewerResolution();
    if (!job.reviewer_id || resolution.state === 'danger') return toast('يجب أن يعالج مسؤول النظام المدير المراجع أولًا');
    if (quality().score < 100) return toast('أكمل عناصر الوصف المطلوبة قبل إرساله للمراجعة');
  }
  if (status === 'MANAGER_APPROVED' && proposals.some(item => item.status === 'PENDING' && item.action !== 'COMMENT')) return toast('اتخذ قرارًا في جميع المقترحات أولًا');
  const payload = {status,updated_by:me.id};
  if (status === 'IN_REVIEW') payload.submitted_at = new Date().toISOString();
  const response = await sb.from('job_descriptions').update(payload).eq('id',job.id).select().maybeSingle();
  if (response.error || !response.data) return toast(response.error?.message || 'تعذر تغيير حالة الوصف');
  job = response.data;
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

async function assignEmployee() {
  const profileId = byId('assignmentEmployee')?.value;
  if (!profileId) return toast('اختر الموظف أولًا');
  const response = await sb.from('employee_job_assignments').upsert({profile_id:profileId,job_description_id:job.id,assigned_by:me.id,updated_by:me.id},{onConflict:'profile_id'});
  if (response.error) return toast(response.error.message);
  await loadRelated();
  render();
  toast(job.status === 'PUBLISHED' ? 'تم الربط وإشعار الموظف' : 'تم الربط؛ سيظهر الوصف للموظف بعد النشر');
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
  byId('editBtn')?.addEventListener('click',() => {editing = !editing; render();});
  byId('saveBtn')?.addEventListener('click',saveDraft);
  byId('submitBtn')?.addEventListener('click',() => transition('IN_REVIEW'));
  byId('managerDoneBtn')?.addEventListener('click',managerDone);
  byId('adminDoneBtn')?.addEventListener('click',() => transition('MANAGER_APPROVED'));
  byId('publishBtn')?.addEventListener('click',() => transition('PUBLISHED'));
  byId('commentBtn')?.addEventListener('click',addComment);
  byId('assignEmployeeBtn')?.addEventListener('click',assignEmployee);
}

async function loadRelated() {
  const responses = await Promise.all([
    sb.from('job_description_change_requests').select('*').eq('job_description_id',job.id).order('created_at'),
    sb.from('job_description_forms').select('usage_note,display_order,form_library(*)').eq('job_description_id',job.id).order('display_order'),
    sb.from('job_description_comments').select('*').eq('job_description_id',job.id).order('created_at'),
    me.role === 'admin' ? sb.from('employee_job_assignments').select('*') : Promise.resolve({data:[]})
  ]);
  proposals = responses[0].data || [];
  forms = (responses[1].data || []).map(item => ({...item.form_library,usage_note:item.usage_note}));
  comments = responses[2].data || [];
  assignments = responses[3].data || [];
}

async function boot() {
  ({data:{session}} = await sb.auth.getSession());
  if (!session?.user) return location.href = '../login.html';
  const profile = await sb.from('profiles').select('id,full_name,email,role,job_title,department,manager_id,active,status').eq('id',session.user.id).single();
  me = profile.data;
  if (!me) return location.href = '../profile/job-description.html';
  window.atwarSyncShellIdentity?.(me,session.user);
  if (me.role === 'admin') {
    const result = await adminApi({action:'list'});
    users = (result.users || []).filter(user => user.active !== false && user.status !== 'inactive');
  } else users = [me];
  const id = new URLSearchParams(location.search).get('id');
  if (!id) throw new Error('لم يتم تحديد الوظيفة المطلوبة');
  const response = await sb.from('job_descriptions').select('*').eq('id',id).maybeSingle();
  if (response.error || !response.data) throw new Error(response.error?.message || 'الوصف غير موجود أو غير متاح');
  job = response.data;
  if (me.role !== 'admin' && job.reviewer_id !== me.id) return location.href = '../profile/job-description.html';
  await loadRelated();
  byId('reviewState').hidden = true;
  byId('reviewApp').hidden = false;
  document.body.style.visibility = 'visible';
  render();
}

document.querySelectorAll('[data-tab]').forEach(button => button.onclick = () => {activeTab = button.dataset.tab; editing = false; render();});
boot().catch(error => {
  console.error(error);
  document.body.style.visibility = 'visible';
  byId('reviewState').textContent = 'تعذر فتح المراجعة: ' + error.message;
});
