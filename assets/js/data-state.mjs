// One presentation for read-only loading, empty and failed reads. Never interpolate server messages as HTML.
export function renderDataState(host,{state='empty',message='',onRetry}={}){
 const node=document.createElement('div');
 node.className=state==='empty'?'atwar-empty-state':'atwar-data-status';node.dataset.state=state;
 node.setAttribute('role',state==='error'?'alert':'status');
 node.setAttribute('aria-live',state==='error'?'assertive':'polite');
 node.setAttribute('aria-atomic','true');
 node.setAttribute('aria-busy',String(state==='loading'));
 const copy=document.createElement('span');copy.textContent=message||(state==='loading'?'جاري تحميل البيانات…':state==='error'?'تعذر تحميل البيانات.':state==='empty'?'لا توجد بيانات.':'');node.append(copy);
 if(state==='error'&&typeof onRetry==='function'){
  const retry=document.createElement('button');retry.type='button';retry.className='atwar-btn';retry.textContent='إعادة المحاولة';
  retry.addEventListener('click',async()=>{
   if(retry.disabled)return;
   retry.disabled=true;node.setAttribute('aria-busy','true');
   try{await onRetry()}catch{if(node.isConnected)copy.textContent=message||'تعذر تحميل البيانات. أعد المحاولة.'}
   finally{if(retry.isConnected){retry.disabled=false;node.setAttribute('aria-busy','false')}}
  });node.append(retry);
 }
 host.replaceChildren(node);return node;
}
