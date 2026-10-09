const root=document.getElementById('employeeJobContent');
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function render(data,profile={},manager=null){
 if(!data.snapshot){root.innerHTML='<section class="panel"><h1>'+esc(data.full_name)+'</h1><h2>لا يوجد وصف وظيفي منشور</h2><p>سيظهر الوصف هنا بعد اعتماد ونشر النسخة المرتبطة بالموظف.</p></section>';return;}
 window.AtwarJobDocument.mount(root,{profile:{...profile,full_name:data.full_name},manager,job:{id:data.job_id,published_snapshot:data.snapshot},snapshot:data.snapshot},{heading:'الملف الوظيفي — '+data.full_name});
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
 const targetResult=await sb.from('profiles').select('department,manager_id').eq('id',uid).maybeSingle();
 const target=targetResult.data||{};
 let manager=null;
 if(target.manager_id===profile.id)manager=profile;
 else if(target.manager_id){const result=await sb.from('profiles').select('full_name').eq('id',target.manager_id).maybeSingle();manager=result.data;}
 render(data,target,manager);
 const measurementLink=document.createElement('a');measurementLink.className='atwar-btn';measurementLink.href='../profile/measurements.html?employee='+encodeURIComponent(uid);measurementLink.textContent='سجل نتائج قياس مؤشرات الأداء';root.prepend(measurementLink);
 }
 }
 }
}catch(error){
 root.innerHTML='<section class="panel"><h1>تعذر عرض الملف الوظيفي</h1><p>'+esc(error.code==='42501'?'هذا الموظف خارج نطاق الفريق المسموح لك بالاطلاع عليه.':'تعذر تحميل الوصف. أعد المحاولة، وإذا استمرت المشكلة تواصل مع مسؤول النظام.')+'</p><button class="atwar-btn" id="retryEmployeeJob">إعادة المحاولة</button></section>';
 document.getElementById('retryEmployeeJob').onclick=()=>location.reload();
}finally{document.body.style.visibility='visible';try{window.lucide?.createIcons();}catch{}}
