// Serializes refreshes from Realtime, local writes, and polling.
// Only one read may run at a time; bursts collapse into one final refresh.
// Also coalesces idle refresh requests arriving in the same microtask turn.
export function createRefreshCoordinator({load,onValue,onError,serialize=JSON.stringify}){
  let active=true;
  let busy=false;
  let queued=false;
  let scheduled=null;
  let lastSerialized;

  const runLoad=async()=>{
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

  const refresh=()=>{
    if(!active)return Promise.resolve();
    if(busy){queued=true;return Promise.resolve();}
    if(scheduled)return scheduled;
    scheduled=Promise.resolve().then(()=>{
      scheduled=null;
      return runLoad();
    });
    return scheduled;
  };

  return {
    refresh,
    dispose(){active=false;queued=false;}
  };
}

// Share only concurrent reads with exactly the same key. Never cache completed
// results: subsequent refreshes must see writes and Realtime changes.
// Each caller still receives the same rejection so its own error handler runs.
export function createSharedInFlightReads(){
  const pending=new Map();
  return {
    read(key,load){
      if(pending.has(key))return pending.get(key);
      const request=Promise.resolve().then(load);
      pending.set(key,request);
      // Register both outcomes to avoid unhandled rejection from a detached
      // finally() promise. Only the original request is returned to callers.
      request.then(
        ()=>{if(pending.get(key)===request)pending.delete(key);},
        ()=>{if(pending.get(key)===request)pending.delete(key);}
      );
      return request;
    }
  };
}
