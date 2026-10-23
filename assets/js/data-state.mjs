// One presentation for read-only loading, empty and failed reads. Never interpolate server messages as HTML.
export function renderDataState(host,{state='empty',message='',onRetry}={}){
 const node=document.createElement('div');
 node.className=state==='empty'?'atwar-empty-state':'atwar-data-status';node.dataset.state=state;
 node.setAttribute('role',state==='error'?'alert':'status');
 const copy=document.createElement('span');copy.textContent=message;node.append(copy);
 if(state==='error'&&typeof onRetry==='function'){
  const retry=document.createElement('button');retry.type='button';retry.className='atwar-btn';retry.textContent='إعادة المحاولة';
  retry.addEventListener('click',async()=>{retry.disabled=true;try{await onRetry()}finally{if(retry.isConnected)retry.disabled=false}});node.append(retry);
 }
 host.replaceChildren(node);return node;
}
