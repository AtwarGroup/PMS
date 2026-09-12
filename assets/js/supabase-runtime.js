(function(){
  let clientPromise=null;
  window.atwarGetSupabase=window.atwarGetSupabase||async function(){
    if(window.ATWAR_SUPABASE) return window.ATWAR_SUPABASE;
    if(clientPromise) return clientPromise;
    clientPromise=(async()=>{
      const cfg=window.ATWAR_SUPABASE_CONFIG;
      if(!cfg?.url||!cfg?.publishableKey) throw new Error('Supabase config unavailable');
      const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
      const sb=createClient(cfg.url,cfg.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
      window.ATWAR_SUPABASE=sb;
      return sb;
    })();
    return clientPromise;
  };
  window.atwarGetCurrentProfile=window.atwarGetCurrentProfile||async function(){
    const sb=await window.atwarGetSupabase();
    const {data:{session},error}=await sb.auth.getSession();
    if(error||!session?.user) return null;
    const {data,error:pErr}=await sb.from('profiles').select('*').eq('id',session.user.id).single();
    if(pErr||!data) return null;
    return {authUser:session.user,profile:data};
  };

  let reporting=false;
  window.atwarReportError=window.atwarReportError||async function(error,type='client_error'){
    if(reporting)return;
    reporting=true;
    try{
      const sb=await window.atwarGetSupabase();
      const {data:{session}}=await sb.auth.getSession();
      if(!session?.user)return;
      const value=error instanceof Error?error:new Error(String(error||'Unknown client error'));
      await sb.from('app_error_logs').insert({
        actor_id:session.user.id,
        page_path:`${location.pathname}${location.search}`.slice(0,500),
        error_type:String(type||'client_error').slice(0,80),
        message:String(value.message||value).slice(0,2000),
        stack:String(value.stack||'').slice(0,6000)||null,
        user_agent:String(navigator.userAgent||'').slice(0,500)||null
      });
    }catch{}finally{reporting=false;}
  };

  window.addEventListener('error',event=>window.atwarReportError(event.error||event.message,'window_error'));
  window.addEventListener('unhandledrejection',event=>window.atwarReportError(event.reason,'unhandled_rejection'));
})();
