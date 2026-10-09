import {mountMeasurements} from './kpi-measurement-page.mjs?v=1.0.0';
const host=document.getElementById('measurementApp');
try{
 const sb=await window.atwarGetSupabase();const {data:{session},error}=await sb.auth.getSession();if(error)throw error;
 if(!session?.user)location.replace('../login.html');else{
  const {data:profile,error:profileError}=await sb.from('profiles').select('id,full_name,email,role,active,status').eq('id',session.user.id).single();
  if(profileError||!profile?.active||profile.status!=='active')throw Error('inactive');window.atwarSyncShellIdentity?.(profile,session.user);
  const employeeId=new URLSearchParams(location.search).get('employee')||profile.id;await mountMeasurements({sb,employeeId,host});
 }
}catch(error){host.innerHTML='<section class="measurement-history"><h1>تعذر فتح سجل القياس</h1><p role="status">'+(error.code==='42501'?'هذا الموظف خارج نطاق صلاحياتك.':'تحقق من الاتصال وحالة الحساب ثم أعد المحاولة.')+'</p><button id="measurementRetry" class="atwar-btn" type="button">إعادة المحاولة</button></section>';document.getElementById('measurementRetry').onclick=()=>location.reload();}
