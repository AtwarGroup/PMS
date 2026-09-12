// Serializes refreshes from Realtime, local writes, and polling.
// Only one read may run at a time; bursts collapse into one final refresh.
export function createRefreshCoordinator({load,onValue,onError,serialize=JSON.stringify}){
  let active=true;
  let busy=false;
  let queued=false;
  let lastSerialized;

  const refresh=async()=>{
    if(!active)return;
    if(busy){queued=true;return;}
    busy=true;
    try{
      const value=await load();
      if(!active)return;
      const serialized=serialize(value);
      if(serialized!==lastSerialized){
        lastSerialized=serialized;
        onValue(value);
      }
    }catch(error){
      if(active)onError?.(error);
    }finally{
      busy=false;
      if(queued&&active){
        queued=false;
        queueMicrotask(refresh);
      }
    }
  };

  return {
    refresh,
    dispose(){active=false;queued=false;}
  };
}
