
function getAtwarSession(){
  try{
    const session=JSON.parse(localStorage.getItem('atwarSession')||'null');
    if(!session||!session.uid||!['employee','manager','admin'].includes(session.role))return null;
    return session;
  }catch{return null}
}

// توافق مؤقت مع الصفحات القديمة التي تستدعي الاسم السابق.
const getAtwarDemoSession=getAtwarSession;

function atwarDepth(){
  const nestedModules=['tasks','completed','team','profile','workspace','follow-up','notifications','search','admin','approvals','organization','my-day','recurring'];
  return nestedModules.some(name=>location.pathname.includes('/'+name+'/')) ? '../' : '';
}

function atwarRoleRank(role){
  const rank=window.ATWAR_ROLE_RANK||{employee:1,manager:2,admin:3};
  return rank[role]||0;
}

function requireAtwarSession(){
  const session=getAtwarSession();
  if(!session){
    if(!location.pathname.endsWith('login.html') && !location.pathname.endsWith('landing.html')){
      location.href=atwarDepth()+'login.html';
    }
    return null;
  }
  return session;
}

function applyAtwarPermissions(){
  const s=requireAtwarSession();
  if(!s)return;

  const requiredPageRole=document.body?.dataset?.minRole;
  if(requiredPageRole && atwarRoleRank(s.role)<atwarRoleRank(requiredPageRole)){
    location.href=atwarDepth()+'home.html';
    return;
  }

  document.querySelectorAll('[data-role-min]').forEach(el=>{
    if(atwarRoleRank(s.role)<atwarRoleRank(el.dataset.roleMin)) el.style.display='none';
  });

  document.querySelectorAll('[data-role-only]').forEach(el=>{
    const allowed=el.dataset.roleOnly.split(',').map(x=>x.trim());
    if(!allowed.includes(s.role)) el.style.display='none';
  });

  document.querySelectorAll('[data-permission]').forEach(el=>{
    if(!Array.isArray(s.permissions) || !s.permissions.includes(el.dataset.permission)) el.style.display='none';
  });

  document.querySelectorAll('[data-user-name]').forEach(el=>el.textContent=s.name||s.email);
  document.querySelectorAll('[data-user-title]').forEach(el=>el.textContent=s.title||'');
  document.querySelectorAll('[data-user-role]').forEach(el=>{
    el.textContent=s.role==='admin'?'مدير النظام':s.role==='manager'?'مدير':'موظف';
  });
  document.querySelectorAll('[data-greeting-name]').forEach(el=>el.textContent=s.name||s.email);

  document.documentElement.dataset.userRole=s.role;
  if(window.lucide) lucide.createIcons();
}

async function atwarLogout(){
  localStorage.removeItem('atwarSession');
  localStorage.removeItem('atwarDemoSession');
  try{
    if(window.ATWAR_SUPABASE?.auth?.signOut) await window.ATWAR_SUPABASE.auth.signOut();
    else if(window.ATWAR_SUPABASE_CONFIG){
      const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
      const c=window.ATWAR_SUPABASE_CONFIG;
      await createClient(c.url,c.publishableKey).auth.signOut();
    }
  }catch(error){console.warn('Supabase sign-out warning:',error)}
  location.href=atwarDepth()+'login.html';
}

async function verifyAtwarSessionWithSupabase(){
  if(!window.atwarGetSupabase)return getAtwarSession();
  try{
    const sb=await window.atwarGetSupabase();
    const {data:{session}}=await sb.auth.getSession();
    if(!session?.user){localStorage.removeItem('atwarSession');localStorage.removeItem('atwarDemoSession');return null;}
    const {data:p,error}=await sb.from('profiles').select('*').eq('id',session.user.id).single();
    if(error||!p||p.active===false||p.status!=='active'||!['employee','manager','admin'].includes(p.role)){
      localStorage.removeItem('atwarSession');localStorage.removeItem('atwarDemoSession');await sb.auth.signOut().catch(()=>{});return null;
    }
    const old=getAtwarSession();
    const verified={uid:p.id,email:session.user.email||p.email||'',name:p.full_name||session.user.email||'المستخدم',title:p.job_title||'',role:p.role,managerId:p.manager_id||null,managerChain:p.manager_chain||{},permissions:Array.isArray(p.permissions)?p.permissions:[],source:'supabase-verified'};
    localStorage.setItem('atwarSession',JSON.stringify(verified));localStorage.removeItem('atwarDemoSession');
    const changed=!old||String(old.uid)!==String(verified.uid)||old.role!==verified.role||JSON.stringify(old.permissions||[])!==JSON.stringify(verified.permissions||[]);
    if(changed&&!sessionStorage.getItem('atwarRoleVerifiedReload')){
      sessionStorage.setItem('atwarRoleVerifiedReload','1');location.reload();return null;
    }
    sessionStorage.removeItem('atwarRoleVerifiedReload');
    return verified;
  }catch(error){console.warn('Session verification warning:',error);return getAtwarSession();}
}

document.addEventListener('DOMContentLoaded',async()=>{
  const verified=await verifyAtwarSessionWithSupabase();
  if(!verified){
    if(!location.pathname.endsWith('login.html')&&!location.pathname.endsWith('landing.html'))location.href=atwarDepth()+'login.html';
    return;
  }
  applyAtwarPermissions();
});


function atwarGoToStart(){
  const s=getAtwarSession();
  if(!s){ location.href=atwarDepth()+'login.html'; return; }
  const starts=window.ATWAR_START_PAGE||{};
  const target=starts[s.role]||'home.html';
  const depth=atwarDepth();
  location.href=depth+target;
}
