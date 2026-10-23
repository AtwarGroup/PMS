(function(){
 const visibility=document.createElement('style');visibility.textContent='[data-module][hidden]{display:none!important}.module-denied-note{padding:16px;border:1px solid var(--atwar-border,#dce5ee);border-radius:12px;background:var(--atwar-surface,#fff);color:var(--atwar-text,#243652);line-height:1.8}';document.head.append(visibility);
 let current=null,pending=null;
 const routeModule=(path=location.pathname)=>{
  const p=new URL(path,location.origin).pathname;
  if(/\/(tasks|completed|recurring|my-day|approvals|attachments)\//.test(p))return 'tasks';
  if(/\/(workspace|follow-up)\//.test(p))return 'workspace';
  if(/\/projects\//.test(p))return 'projects';
  if(/\/policies\//.test(p))return 'policies';
  if(/\/(communication|communication-trial)\//.test(p))return 'communication';
  if(/\/team\//.test(p)||/\/admin\/employees\.html$/.test(p))return 'employees';
  if(/\/job-library\//.test(p))return 'job_library';
  if(/\/fleet\//.test(p))return 'fleet';
  if(/\/recruitment\//.test(p))return 'recruitment';
  for(const m of current?.catalog||[]){const route=new URL(m.path,location.origin+'/').pathname,dir=route.slice(0,route.lastIndexOf('/'));if(p===route||dir&&!['/admin','/profile'].includes(dir)&&p.startsWith(dir+'/'))return m.key;}
  return '';
 };
 const allowed=key=>!key||!!current&&(current.allowed||[]).includes(key)&&!!current.catalog?.some(m=>m.key===key&&m.ready);
 function apply(){
  if(!current)return;
  const nav=document.querySelector('.atwar-nav');
  if(nav)for(const m of current.catalog){if(!m.ready||!allowed(m.key)||['tasks','workspace','projects','policies','communication','employees','job_library'].includes(m.key)||nav.querySelector(`[data-module="${m.key}"]`)||[...nav.querySelectorAll('a[href]')].some(a=>new URL(a.getAttribute('href'),location.href).pathname===new URL(m.path,location.origin+'/').pathname))continue;const link=document.createElement('a');link.href=new URL(m.path,location.origin+'/').href;link.dataset.module=m.key;const icon=document.createElement('i');icon.setAttribute('data-lucide',m.icon||'layout-grid');const label=document.createElement('span');label.textContent=m.label;link.append(icon,label);nav.append(link);window.lucide?.createIcons();}
  for(const anchor of document.querySelectorAll('a[href]')){
   const url=new URL(anchor.getAttribute('href'),location.href);if(url.origin!==location.origin)continue;
   const key=routeModule(url.pathname);if(key){anchor.hidden=!allowed(key);anchor.dataset.module=key;}
  }
  for(const node of document.querySelectorAll('[data-module]'))node.hidden=!allowed(node.dataset.module);
  document.documentElement.dataset.modulesReady='true';
 }
 async function load(sb,{force=false}={}){
  if(current&&!force)return current;if(pending)return pending;
  pending=(async()=>{const {data:{session},error}=await sb.auth.getSession();if(error)throw error;if(!session?.user){current=null;return null;}
   const {data,error:denied}=await sb.rpc('account_module_context');if(denied)throw denied;
   if(!data||data.profile_id!==session.user.id||!Array.isArray(data.allowed)||!Array.isArray(data.catalog))throw Error('تعذر التحقق من وحدات الحساب.');
   current=data;apply();return current;
  })();try{return await pending;}finally{pending=null;}
 }
 async function guard(sb){
  if(/\/login\.html$/.test(location.pathname))return;
  try{const context=await load(sb);if(!context)return;
   const unit=routeModule();if(unit&&!allowed(unit)){
    const home=new URL(location.pathname.includes('/admin/')||/\/(tasks|completed|recurring|my-day|approvals|attachments|workspace|follow-up|projects|policies|communication|communication-trial|team|job-library|fleet|recruitment)\//.test(location.pathname)?'../home.html':'home.html',location.href);
    home.searchParams.set('access','denied');location.replace(home.href);throw Error('ATWAR_MODULE_DENIED');
   }
  }catch(error){if(error?.code==='42501'&&!current){const nested=/\/(admin|tasks|completed|recurring|my-day|approvals|attachments|workspace|follow-up|projects|policies|communication|communication-trial|team|job-library|fleet|recruitment|profile|notifications|search)\//.test(location.pathname);location.replace(new URL(nested?'../login.html':'login.html',location.href).href);}if(routeModule())document.body.style.visibility='hidden';throw error;}
 }
 window.AtwarModules=Object.freeze({routeModule,allowed,apply,load,guard,get context(){return current;}});
 document.addEventListener('DOMContentLoaded',apply);
})();
