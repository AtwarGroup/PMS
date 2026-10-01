import {mountChangeReview} from './employee-job-changes.js?v=2.5.39';
const sb=await window.atwarGetSupabase(),host=document.getElementById('employeeChangeReview');
try{const {data:{session}}=await sb.auth.getSession();if(!session?.user)location.href='../login.html';else{const {data:profile,error}=await sb.from('profiles').select('*').eq('id',session.user.id).single();if(error)throw error;window.atwarSyncShellIdentity?.(profile,session.user);await mountChangeReview(host,{sb,profile});}}
catch(error){host.textContent=error.message||'تعذر تحميل الطلبات.';}
