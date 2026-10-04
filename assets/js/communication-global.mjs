// Production alerts; active profile and current conversation membership are required.
export async function startCommunicationAlerts(){
 if(document.readyState==='loading')await new Promise(resolve=>document.addEventListener('DOMContentLoaded',resolve,{once:true}));
 if(typeof window.atwarGetSupabase!=='function')return;
 const sb=await window.atwarGetSupabase();let activity=Date.now();const device=crypto.randomUUID();const touch=()=>{activity=Date.now();};
 let channel,timer,subscription,stopped=false,busy=false,rerun=false,actor;
 const clear=()=>{stopped=true;document.removeEventListener('pointerdown',touch);document.removeEventListener('keydown',touch);clearInterval(timer);subscription?.unsubscribe();if(channel)void sb.removeChannel(channel);document.querySelectorAll('[data-communication-alert]').forEach(e=>e.remove());};
 const {data:{user},error}=await sb.auth.getUser();if(error||!user)return;actor=user.id;
 const auth=sb.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(session?.user?.id&&session.user.id!==actor))clear();});subscription=auth.data.subscription;
 const {data:allowed,error:gate}=await sb.rpc('communication_status');if(gate||!allowed||stopped){clear();return;}
 document.addEventListener('pointerdown',touch,{passive:true});document.addEventListener('keydown',touch,{passive:true});
 async function refresh(){
  if(stopped)return;if(busy){rerun=true;return;}busy=true;
  try{
   if(!document.hidden)await sb.functions.invoke('communication',{body:{path:'action',data:{action:'presence',data:{device,active:activity,viewing:null}}}});if(stopped)return;
   const {data:rows,error}=await sb.from('notifications').select('id').eq('type','communication').is('read_at',null).order('created_at',{ascending:false}).limit(20);if(error||stopped)return;
   for(const row of [...(rows||[])].reverse()){
    const {data,error}=await sb.functions.invoke('communication',{body:{path:'action',data:{action:'notificationClaim',data:{id:row.id}}}});if(error||stopped||!data?.show)continue;
    const toast=document.createElement('button');toast.type='button';toast.dataset.communicationAlert=row.id;toast.textContent='رسالة جديدة في التواصل — اضغط لفتحها';
    toast.style.cssText='position:fixed;inset-inline-end:24px;bottom:24px;z-index:9999;max-width:calc(100vw - 48px);padding:16px 22px;border:1px solid #dbe3ef;border-radius:12px;background:#fff;color:#0b2447;box-shadow:0 8px 30px #0b244726;font-family:Tajawal,sans-serif;cursor:pointer';
    document.querySelectorAll('[data-communication-alert]').forEach(e=>e.remove());document.body.append(toast);
    toast.onclick=async()=>{const {data:route,error}=await sb.rpc('communication_notification_open',{p_id:row.id});if(error||stopped||!route){toast.remove();return;}location.href=new URL('../../communication/?conversation='+encodeURIComponent(route.conversation)+'&message='+encodeURIComponent(route.message),import.meta.url).href;};
    if(data.desktop&&typeof Notification!=='undefined'&&Notification.permission==='granted'&&!document.hasFocus()){const desktop=new Notification('رسالة جديدة في التواصل',{body:'افتح النظام لقراءة الرسالة',tag:'atwar-communication'});desktop.onclick=()=>{window.focus();toast.click();desktop.close();};}
    if(data.sound&&window.atwarNotificationSound?.enabled())window.atwarNotificationSound.play('new');setTimeout(()=>toast.remove(),10000);
   }
   document.querySelector('atwar-header')?._atwarRefreshNotifications?.();
  }catch{}finally{busy=false;if(rerun){rerun=false;void refresh();}}
 }
 channel=sb.channel('communication-global:'+actor).on('postgres_changes',{event:'*',schema:'public',table:'communication_revisions',filter:'user_id=eq.'+actor},()=>void refresh()).subscribe(status=>{if(status==='SUBSCRIBED')void refresh();});
 timer=setInterval(()=>void refresh(),20000);document.addEventListener('visibilitychange',refresh);window.addEventListener('online',refresh);
 window.addEventListener('pagehide',()=>{clear();auth.data.subscription.unsubscribe();document.removeEventListener('visibilitychange',refresh);window.removeEventListener('online',refresh);},{once:true});await refresh();
}
