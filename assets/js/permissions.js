
function getAtwarDemoSession(){
  try{return JSON.parse(localStorage.getItem('atwarDemoSession')||'null')}catch{return null}
}

function atwarDepth(){
  return (
    location.pathname.includes('/tasks/') ||
    location.pathname.includes('/team/') ||
    location.pathname.includes('/profile/')
  ) ? '../' : '';
}

function atwarRoleRank(role){
  const rank=window.ATWAR_ROLE_RANK||{employee:1,manager:2,admin:3};
  return rank[role]||0;
}

function requireAtwarSession(){
  const session=getAtwarDemoSession();
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
    location.href=atwarDepth()+'index.html';
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

function atwarLogout(){
  localStorage.removeItem('atwarDemoSession');
  location.href=atwarDepth()+'landing.html';
}

document.addEventListener('DOMContentLoaded',applyAtwarPermissions);


function atwarGoToStart(){
  const s=getAtwarDemoSession();
  if(!s){ location.href=atwarDepth()+'login.html'; return; }
  const starts=window.ATWAR_START_PAGE||{};
  const target=starts[s.role]||'index.html';
  const depth=atwarDepth();
  location.href=depth+target;
}
