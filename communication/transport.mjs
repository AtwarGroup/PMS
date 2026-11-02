// Retry only reads and explicitly idempotent writes, always reusing the same payload.
export async function invokeCommunication(sb,path,data,{timeoutMs=15000,wait=ms=>new Promise(r=>setTimeout(r,ms))}={}){
 const read=['accounts','state','file','history','message'].includes(path);
 const safeWrite=path==='action'&&(['presence','read'].includes(data?.action)||(data?.action==='message'&&/^[a-zA-Z0-9-]{8,100}$/.test(data?.data?.clientId||'')));
 const attempts=read||safeWrite?2:1,deadline=Date.now()+timeoutMs;
 for(let attempt=0;attempt<attempts;attempt++){
  const controller=new AbortController();let timedOut=false;
  const timer=setTimeout(()=>{timedOut=true;controller.abort();},Math.max(1,deadline-Date.now()));
  try{
   let result;
   try{result=await sb.functions.invoke('communication',{body:{path,data},signal:controller.signal});}
   catch(error){result={error};}
   if(!result.error)return result.data;
   const error=result.error,status=error.context?.status;let body;
   try{body=await error.context?.clone().json();}catch{}
   const transient=!status||[502,503,504].includes(status);
   if(transient&&!timedOut&&attempt+1<attempts&&Date.now()+300<deadline){clearTimeout(timer);await wait(300*(attempt+1));continue;}
   const failure=new Error(body?.error||(transient?(timedOut?'تأخر الاتصال بخدمة المحادثات. أعد المحاولة بعد لحظات.':'تعذر الاتصال بخدمة المحادثات مؤقتًا. أعد المحاولة بعد لحظات.'):error.message||'تعذر تنفيذ الإجراء.'));
   failure.status=status;failure.retryable=transient;throw failure;
  }finally{clearTimeout(timer);}
 }
}
