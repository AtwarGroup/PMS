/* Shared job-description display. Workflow actions remain in their owning pages. */
(() => {
const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const list=value=>Array.isArray(value)?value:[],itemText=item=>typeof item==='string'?item:(item?.text||item?.name||item?.title||'');
const valueOf=(item,keys,fallback='')=>keys.map(key=>item?.[key]).find(value=>value!==undefined&&value!==null&&value!=='')??fallback;
const authorityTone=type=>/اعتماد|قرار/.test(type)?'approve':/تنفيذ|إجراء/.test(type)?'execute':/رفع|توصية|تشاور/.test(type)?'consult':'view';
const metaCell=(label,value)=>value?`<div class="hybrid-meta"><span>${esc(label)}</span><b>${esc(value)}</b></div>`:'';
function scoreScale(item){
  const raw=item?.scale||item?.scoring||item?.levels;
  if(!Array.isArray(raw)||raw.length!==5)return `<div class="kpi-five-levels" aria-label="حدود التقييم لم تعتمد بعد">${[1,2,3,4,5].map(level=>`<div class="kpi-level"><b>${level}</b><span>—</span></div>`).join('')}</div><span class="kpi-unset">حدود التقييم بانتظار الاعتماد</span>`;
  return `<div class="kpi-five-levels">${raw.map((level,index)=>`<div class="kpi-level"><b>${esc(level?.score||level?.level||index+1)}</b><span>${esc(level?.label||level?.range||level?.value||'غير محدد')}</span></div>`).join('')}</div>`;
}
const KPI_WEIGHT_PROPOSAL={jobId:'06c2bfbf-9fe6-478b-a977-065a42c28586',revision:14,names:['التجديد قبل الاستحقاق','إنجاز المعاملات في الموعد','استمرارية الخدمات','دقة سجل الأصول والعهد','الالتزام بالتفويض'],weights:[25,20,20,20,15]};
function suggestedWeights(rows,job){
  const proposal=KPI_WEIGHT_PROPOSAL;
  return job?.id===proposal.jobId&&Number(job?.published_snapshot?.revision)===proposal.revision&&rows.length===proposal.names.length&&rows.every((row,index)=>itemText(row)===proposal.names[index])?proposal.weights:null;
}
function kpiFramework(rows,job){
  const numericWeight=value=>{const v=Number(String(value??'').replace('%','').trim());return Number.isFinite(v)&&v>0?v:null};
  const weights=rows.map(row=>numericWeight(row?.weight));
  const completeWeights=weights.every(value=>value!==null)&&Math.abs(weights.reduce((sum,value)=>sum+(value||0),0)-100)<.01;
  const proposal=weights.every(value=>value===null)?suggestedWeights(rows,job):null;
  return `<section class="kpi-framework kpi-framework-v2"><div><small>BALANCED SCORECARD FRAMEWORK</small><h5>بطاقة قياس مؤشرات الأداء KPI's</h5><p>${esc(job?.published_snapshot?.title||job?.title||'الوصف الوظيفي المنشور')} • سلم التقييم الخماسي (١ إلى ٥)</p></div><div class="kpi-framework-stat"><span>إجمالي الوزن المعتمد</span><b>${completeWeights?'100%':proposal?'100% مقترحة':'غير مكتمل'}</b></div></section><div class="kpi-table-scroll"><table class="kpi-table"><thead><tr><th scope="col">#</th><th scope="col">المستهدف (KPI)</th><th scope="col">وحدة التقييم</th><th scope="col">الهدف وطريقة القياس</th><th scope="col">سلم التقييم (١ - ٥)</th><th scope="col">الوزن %</th><th scope="col">المستهدف</th><th scope="col">المصدر</th></tr></thead><tbody>${rows.map((item,index)=>`<tr><td class="kpi-index">${index+1}</td><td><b>${esc(itemText(item))}</b></td><td>${esc(valueOf(item,['unit'],'غير محددة'))}</td><td>${esc(valueOf(item,['measure','formula'],'لم تحدد طريقة القياس'))}</td><td>${scoreScale(item)}</td><td>${weights[index]!==null?`${weights[index]}%`:proposal?`${proposal[index]}% <span class="kpi-unset">مقترح</span>`:'—'}</td><td class="kpi-target">${esc(valueOf(item,['target'],'—'))}</td><td>${esc(valueOf(item,['source','data_source'],'غير محدد'))}</td></tr>`).join('')}</tbody></table></div><p class="kpi-policy-note">الأوزان الموسومة «مقترح» توصية مراجعة لهذا الإصدار، وليست جزءًا من الوصف المعتمد. لا يُختار مستوى تقييم أو تُحتسب نتيجة دون حدود وقياس فعلي معتمد.</p>`;
}
function section(mode,context){
  const {profile={},manager,job={},snapshot={},content=snapshot.content||{},revision=snapshot.revision||job.revision}=context;
  const title={},subtitle={},body={};
  const empty=message=>`<div class="inline-empty">${esc(message)}</div>`,ack='';
  if(mode==='description'){
    title.textContent='الوصف الوظيفي';subtitle.textContent='الغرض والهوية التنظيمية للوظيفة المعتمدة.';
    const q=content.qualifications||{};body.innerHTML=`<div class="job-purpose-card"><span class="job-purpose-icon"><i data-lucide="compass"></i></span><div><h4>الغرض من الوظيفة</h4><p>${esc(snapshot.purpose||'لم يُسجل الغرض الوظيفي.')}</p></div></div><div class="job-facts"><div class="job-fact"><span>المسمى الوظيفي</span><b>${esc(snapshot.title||job.title||'—')}</b></div><div class="job-fact"><span>الإدارة</span><b>${esc(profile.department||snapshot.family||'—')}</b></div><div class="job-fact"><span>المدير المباشر</span><b>${esc(manager?.full_name||'لا يوجد')}</b></div><div class="job-fact"><span>الإصدار المعتمد</span><b>${esc(revision)}</b></div>${q.education?`<div class="job-fact"><span>المؤهل</span><b>${esc(q.education)}</b></div>`:''}${q.experience?`<div class="job-fact"><span>الخبرة</span><b>${esc(q.experience)}</b></div>`:''}${q.skills?`<div class="job-fact"><span>المهارات</span><b>${esc(q.skills)}</b></div>`:''}</div>${ack}`;
  }else if(mode==='tasks'){
    title.textContent='المهام والمسؤوليات';subtitle.textContent='عرض تنفيذي مختصر، مع تفاصيل المخرجات والتقارير عند توفرها.';const rows=list(content.responsibilities),reports=list(content.reports),colors=[['#edf5ff','#1769e0'],['#e7f8f1','#15946a'],['#fff2df','#d47b00'],['#f0ecff','#7656d7']];
    const taskCards=rows.map((item,index)=>{const output=valueOf(item,['output','deliverable','result']),evidence=valueOf(item,['evidence','proof']),frequency=valueOf(item,['frequency','cycle']),tone=colors[index%colors.length];return `<details class="hybrid-details" style="--task-bg:${tone[0]};--task-accent:${tone[1]}"><summary><span class="task-accent">${String(index+1).padStart(2,'0')}</span><span class="task-title">${esc(itemText(item))}</span></summary><div class="hybrid-details-body"><div class="hybrid-meta-grid">${metaCell('نوع المسؤولية',valueOf(item,['type'],'تنفيذ'))}${metaCell('الدورية',frequency)}${metaCell('المخرج المتوقع',output)}${metaCell('دليل الإنجاز',evidence)}</div>${!output&&!evidence&&!frequency?'<span>هذه المسؤولية منشورة كنطاق عمل معتمد دون تفاصيل إضافية.</span>':''}</div></details>`}).join('');
    const reportCards=reports.length?`<div class="hybrid-section-title"><h5><i data-lucide="files"></i>المخرجات والتقارير المعتمدة</h5><span>${reports.length} مخرجات</span></div><div class="report-grid">${reports.map(report=>`<article class="report-card"><h6>${esc(itemText(report))}</h6><p>${esc(valueOf(report,['frequency'],'حسب الحاجة'))} • إلى ${esc(valueOf(report,['recipient'],'الجهة المعتمدة'))}</p>${report?.display_rule?`<p>${esc(report.display_rule)}</p>`:''}</article>`).join('')}</div>`:'';
    body.innerHTML=rows.length?`<div class="hybrid-summary"><div class="hybrid-summary-card"><span>إجمالي المسؤوليات</span><b>${rows.length}</b></div><div class="hybrid-summary-card" style="--summary-accent:#15946a"><span>المخرجات والتقارير</span><b>${reports.length}</b></div></div><div class="authority-hybrid-list">${taskCards}</div>${reportCards}${ack}`:empty('لا توجد مهام منشورة في هذه النسخة.');
  }else if(mode==='authority'){
    title.textContent='مصفوفة الصلاحيات المعتمدة';subtitle.textContent='ما يمكنك الاطلاع عليه أو تنفيذه أو اعتماده، وحدود التصعيد.';const rows=list(content.authorities),types=[...new Set(rows.map(item=>valueOf(item,['type'],'اطلاع')))];
    body.innerHTML=rows.length?`<div class="hybrid-summary"><div class="hybrid-summary-card"><span>إجمالي الصلاحيات</span><b>${rows.length}</b></div><div class="hybrid-summary-card" style="--summary-accent:#7656d7"><span>مستويات الصلاحية</span><b>${types.length}</b></div></div><div class="authority-hybrid-list">${rows.map((item,index)=>{const type=valueOf(item,['type'],'اطلاع'),tone=authorityTone(type);return `<details class="hybrid-details authority-tone-${tone}"${index===0?' open':''}><summary><span class="task-accent" style="--task-bg:var(--authority-bg);--task-accent:var(--authority-accent)"><i data-lucide="shield-check"></i></span><span class="task-title">${esc(itemText(item))}</span><span class="authority-type">${esc(type)}</span></summary><div class="hybrid-details-body"><div class="hybrid-meta-grid">${metaCell('نطاق الصلاحية',valueOf(item,['scope'],'وفق الدور الوظيفي'))}${metaCell('الحدود والضوابط',valueOf(item,['limit'],'وفق التفويض المعتمد'))}${metaCell('مسار التصعيد',valueOf(item,['escalation'],'المدير المباشر عند تجاوز الحد'))}${metaCell('دليل الإجراء',valueOf(item,['evidence']))}</div></div></details>`}).join('')}</div>${ack}`:empty('لا توجد صلاحيات منشورة في هذه النسخة.');
  }else{
    title.textContent="بطاقة قياس مؤشرات الأداء KPI's";subtitle.textContent='إطار بطاقة الأداء المتوازن بسلم التقييم الخماسي للمؤشرات المنشورة.';const rows=list(content.kpis);
    body.innerHTML=rows.length?`${kpiFramework(rows,job)}${ack}`:empty('لا توجد مؤشرات أداء منشورة في هذه النسخة.');
  }
  return {title:title.textContent,subtitle:subtitle.textContent,html:body.innerHTML};
}

function mount(host,context,{mode='description',status='منشور ومعتمد',heading='الملف الوظيفي المعتمد',footer=''}={}){
 const c=context.content||context.snapshot?.content||{},s=context.snapshot||{},modes=[['description','الوصف الوظيفي','file-badge',s.title||context.job?.title||'النسخة الوظيفية'],['tasks','المهام والمسؤوليات','list-checks',list(c.responsibilities).length+' مهمة ومسؤولية'],['authority','حدود الصلاحيات','shield-check',list(c.authorities).length+' صلاحية وحد'],['performance',"بطاقة قياس مؤشرات الأداء KPI’s",'chart-no-axes-combined',list(c.kpis).length+' مؤشر قياس']];
 host.classList.add('atwar-job-document');
 host.innerHTML=`<div class="professional-head"><div><h3><i data-lucide="badge-check"></i> ${esc(heading)}</h3><p class="document-subtitle">مهام الوظيفة وحدود الصلاحيات وآلية قياس الأداء في النسخة الوظيفية.</p></div><span class="job-publication-state">${esc(status)}</span></div><div class="professional-links">${modes.map(([key,label,icon,detail])=>`<button type="button" class="professional-link" data-job-section="${key}"><span class="professional-icon"><i data-lucide="${icon}"></i></span><span><b>${esc(label)}</b><small>${esc(detail)}</small></span></button>`).join('')}</div><section class="profile-job-viewer" aria-live="polite"><div class="profile-job-viewer-head"><div><h4 data-job-title></h4><p data-job-subtitle></p></div></div><div class="profile-job-viewer-body" data-job-body></div></section>${footer}`;
 const select=key=>{const view=section(key,context);host.querySelector('[data-job-title]').textContent=view.title;host.querySelector('[data-job-subtitle]').textContent=view.subtitle;host.querySelector('[data-job-body]').innerHTML=view.html;host.querySelectorAll('[data-job-section]').forEach(b=>{b.classList.toggle('active',b.dataset.jobSection===key);b.setAttribute('aria-pressed',String(b.dataset.jobSection===key));});window.lucide?.createIcons();};
 host.querySelectorAll('[data-job-section]').forEach(b=>b.onclick=()=>select(b.dataset.jobSection));select(mode);
 return {select};
}
window.AtwarJobDocument={section,mount};
})();
