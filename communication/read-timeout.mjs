// Bound read-only requests so startup can retry instead of remaining pending forever.
export async function withReadTimeout(request,timeoutMs=15000){
 let timer;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('تأخر الاتصال بالخادم. ستتم إعادة المحاولة تلقائيًا.')),timeoutMs);});
 try{return await Promise.race([request,timeout]);}finally{clearTimeout(timer);}
}
