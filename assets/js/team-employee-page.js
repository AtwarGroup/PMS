const root=document.getElementById('employeeJobContent');
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const itemText=item=>typeof item==='string'?item:(item?.text||item?.name||item?.title||'');
const list=value=>Array.isArray(value)?value:[];
const details=item=>typeof item==='object'&&item?Object.entries(item).filter(([key,value])=>!['text','name','title'].includes(key)&&typeof value==='string'&&value).map(([key,value])=>'<div class="task-sub">'+esc(({type:'النوع',limit:'الحد',scope:'النطاق',evidence:'التوثيق',escalation:'التصعيد',measure:'طريقة القياس',target:'المستهدف',frequency:'الدورية',recipient:'المستلم',display_rule:'طريقة العرض',unit:'الوحدة',source:'المصدر'})[key]||key)+': '+esc(value)+'</div>').join(''):'';
function section(title,items){
 return '<section class="panel" style="margin-top:16px"><h2>'+esc(title)+'</h2>'+ (list(items).length?list(items).map(item=>'<div class="duty">'+esc(itemText(item))+details(item)+'</div>').join(''):'<p>لم تُسجل بنود في النسخة المنشورة.</p>')+'</section>';
}
function render(data){
 const s=data.snapshot;
 if(!s){root.innerHTML='<section class="panel"><h1>'+esc(data.full_name)+'</h1><h2>لا يوجد وصف وظيفي منشور</h2><p>سيظهر الوصف هنا بعد اعتماد ونشر النسخة المرتبطة بالموظف.</p></section>';return;}
 const c=s.content||{};
 root.innerHTML='<section class="employee-hero"><h1 class="emp-name">'+esc(data.full_name)+'</h1><h2>'+esc(s.title||data.job_title)+'</h2><p class="emp-meta">منشور ومعتمد • الإصدار '+esc(s.revision)+' • '+esc(s.job_code)+'</p></section>'+
 '<section class="panel" style="margin-top:16px"><h2>الغرض من الوظيفة</h2><p style="line-height:1.9;white-space:pre-wrap">'+esc(s.purpose||'لم يسجل الغرض الوظيفي.')+'</p></section>'+
 section('المهام والمسؤوليات',c.responsibilities)+section('الصلاحيات والحدود',c.authorities)+section("بطاقة قياس مؤشرات الأداء KPI’s",c.kpis)+section('التقارير',c.reports)+
 '<section class="panel" style="margin-top:16px"><h2>المؤهلات والمهارات</h2>'+Object.entries(c.qualifications||{}).map(([key,value])=>'<div class="info-row"><span class="info-label">'+esc(({education:'المؤهل',experience:'الخبرة',skills:'المهارات',languages:'اللغات'})[key]||key)+'</span><span class="info-value">'+esc(value)+'</span></div>').join('')+'</section>';
}
try{
 const sb=await window.atwarGetSupabase();
 const {data:{session},error:sessionError}=await sb.auth.getSession();
 if(sessionError||!session?.user){location.replace('../login.html');}
 else{
 const {data:profile,error:profileError}=await sb.from('profiles').select('*').eq('id',session.user.id).single();
 if(profileError||!profile||profile.active===false||profile.status==='inactive'||!['manager','admin'].includes(profile.role)){location.replace('../home.html');}
 else{
 window.atwarSyncShellIdentity?.(profile,session.user);
 const uid=new URLSearchParams(location.search).get('uid');
 if(!uid){location.replace('index.html');}
 else{
 const {data,error}=await sb.rpc('get_team_employee_job',{p_profile_id:uid});
 if(error)throw error;
 render(data);
 }
 }
 }
}catch(error){
 root.innerHTML='<section class="panel"><h1>تعذر عرض الملف الوظيفي</h1><p>'+esc(error.code==='42501'?'هذا الموظف خارج نطاق الفريق المسموح لك بالاطلاع عليه.':'تعذر تحميل الوصف. أعد المحاولة، وإذا استمرت المشكلة تواصل مع مسؤول النظام.')+'</p><button class="atwar-btn" id="retryEmployeeJob">إعادة المحاولة</button></section>';
 document.getElementById('retryEmployeeJob').onclick=()=>location.reload();
}finally{document.body.style.visibility='visible';try{window.lucide?.createIcons();}catch{}}
