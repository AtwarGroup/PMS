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
})();
