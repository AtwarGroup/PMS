(function(){
  const validRoles=new Set(['employee','manager','admin']);
  const rank={employee:1,manager:2,admin:3};
  let cached=null;
  async function load({force=false}={}){
    if(cached&&!force)return cached;
    const sb=await window.atwarGetSupabase();
    const {data:{session},error:sessionError}=await sb.auth.getSession();
    if(sessionError||!session?.user)return null;
    const {data:profile,error:profileError}=await sb.from('profiles').select('id,email,full_name,role,job_title,department,manager_id,permissions,active,status,employee_code,join_date,work_location,employment_type,job_description_id').eq('id',session.user.id).maybeSingle();
    if(profileError||!profile||profile.active===false||profile.status==='inactive'||!validRoles.has(profile.role))return null;
    cached={sb,session,user:session.user,profile};window.atwarSyncShellIdentity?.(profile,session.user);return cached;
  }
  async function requireSession({loginPath='../login.html',minRole='employee',permission='',redirectPath=''}={}){
    const context=await load();
    if(!context){location.replace(loginPath);return null}
    const allowed=(rank[context.profile.role]||0)>=(rank[minRole]||0)&&(!permission||(context.profile.permissions||[]).includes(permission));
    if(!allowed){location.replace(redirectPath||loginPath);return null}
    return context;
  }
  function clear(){cached=null}
  window.AtwarSession=Object.freeze({load,require:requireSession,clear,rank});
})();
