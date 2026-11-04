const escape=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function ensureAttachmentStyles(){
 if(typeof document==='undefined'||document.querySelector('link[data-attachment-viewer]'))return;
 const link=document.createElement('link');link.rel='stylesheet';link.dataset.attachmentViewer='1';link.href=new URL('../css/attachment-viewer.css?v=1',import.meta.url).href;document.head.append(link);
}
export function attachmentActions(name,id,{key='file',buttonClass='rec-btn secondary'}={}){
 ensureAttachmentStyles();
 if(!/^[a-z][a-z0-9-]*$/.test(key))throw Error('Invalid attachment action');
 return `<span class="atwar-attachment"><span class="atwar-attachment-name">${escape(name)}</span><span class="atwar-attachment-actions"><button type="button" class="${escape(buttonClass)}" data-${key}="${escape(id)}" aria-label="استعراض ${escape(name)}">استعراض</button><button type="button" class="${escape(buttonClass)}" data-${key}-download="${escape(id)}" aria-label="تنزيل ${escape(name)}">تنزيل</button></span></span>`;
}
export function attachmentMime(name,type=''){
 const types={pdf:'application/pdf',png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',webp:'image/webp',gif:'image/gif',txt:'text/plain'};
 return types[String(name||'').split('.').pop().toLowerCase()]||type||'application/octet-stream';
}
export function downloadAttachment(file){
 const blob=file.blob||new Blob([Uint8Array.from(atob(file.base64.replace(/\s/g,'')),c=>c.charCodeAt(0))],{type:file.mime});
 const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=file.name||'attachment';document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000).unref?.();
}
export function storedAttachment(sb,bucket,path,name,{download=false,mime=''}={}){
 const load=async()=>{const {data,error}=await sb.storage.from(bucket).download(path);if(error)throw error;return {name,mime,blob:data};};
 return download?load().then(downloadAttachment):openAttachmentViewer(load);
}
// Preview uses the same protected read as downloading, without a public file URL.
export async function openAttachmentViewer(load){
 ensureAttachmentStyles();
 const previous=document.activeElement,viewer=document.createElement('dialog');viewer.className='fleet-attachment-viewer';viewer.setAttribute('aria-label','معاينة المرفق');
 const header=document.createElement('header'),title=document.createElement('h2'),close=document.createElement('button');title.textContent='معاينة المرفق';close.type='button';close.className='fleet-btn secondary';close.textContent='إغلاق المعاينة';header.append(title,close);
 const state=document.createElement('p');state.setAttribute('role','status');state.textContent='جارٍ تحميل المعاينة…';
 const content=document.createElement('div');content.className='fleet-attachment-content';const actions=document.createElement('div');actions.className='fleet-action-buttons';viewer.append(header,state,actions,content);document.body.append(viewer);
 let url=null,pdfTask=null,renderTask=null;close.onclick=()=>viewer.close();viewer.addEventListener('close',()=>{if(url)URL.revokeObjectURL(url);renderTask?.cancel();void pdfTask?.destroy();viewer.remove();if(previous?.isConnected)previous.focus();},{once:true});viewer.addEventListener('keydown',e=>{if(e.key==='Escape')e.stopPropagation();});viewer.showModal();
 try{
  const file=await load();if(!viewer.isConnected)return;
  const blob=file.blob||new Blob([Uint8Array.from(atob(file.base64.replace(/\s/g,'')),c=>c.charCodeAt(0))],{type:file.mime});
  const mime=attachmentMime(file.name,file.mime||blob.type),bytes=new Uint8Array(await blob.arrayBuffer());if(!viewer.isConnected)return;
  url=URL.createObjectURL(new Blob([bytes],{type:mime}));title.textContent=file.name;
  const download=document.createElement('a');download.className='fleet-btn secondary';download.textContent='تنزيل';download.href=url;download.download=file.name;
  const tab=document.createElement('a');tab.className='fleet-btn secondary';tab.textContent='فتح في تبويب جديد';tab.href=url;tab.target='_blank';tab.rel='noopener noreferrer';actions.append(download,tab);
  if(mime==='application/pdf'){
   state.textContent='جارٍ تجهيز صفحات PDF…';
   const pdfjs=await import('../vendor/pdfjs-6.5.438/build/pdf.min.mjs');if(!viewer.isConnected)return;
   const base=new URL('../vendor/pdfjs-6.5.438/',import.meta.url);pdfjs.GlobalWorkerOptions.workerSrc=new URL('build/pdf.worker.min.mjs',base).href;
   pdfTask=pdfjs.getDocument({data:bytes,cMapUrl:new URL('cmaps/',base).href,cMapPacked:true,standardFontDataUrl:new URL('standard_fonts/',base).href,wasmUrl:new URL('wasm/',base).href,iccUrl:new URL('iccs/',base).href,disableWorkerRendering:true,enableXfa:false});
   const pdf=await pdfTask.promise;if(!viewer.isConnected)return;
   const controls=document.createElement('div');controls.className='fleet-pdf-controls';const canvas=document.createElement('canvas');canvas.dir='ltr';canvas.style.direction='ltr';canvas.setAttribute('role','img');canvas.setAttribute('aria-label','صفحة من ملف '+file.name);content.append(controls,canvas);
   let pageNumber=1,zoom=1,rendering=false;
   const button=(label,action)=>{const b=document.createElement('button');b.type='button';b.className='fleet-btn secondary';b.textContent=label;b.onclick=()=>action().catch(error=>{if(viewer.isConnected)state.textContent='تعذر عرض الصفحة: '+error.message;});return b;};
   const before=button('الصفحة السابقة',async()=>{pageNumber--;await render();}),after=button('الصفحة التالية',async()=>{pageNumber++;await render();}),smaller=button('تصغير',async()=>{zoom=Math.max(.5,zoom-.25);await render();}),larger=button('تكبير',async()=>{zoom=Math.min(2.5,zoom+.25);await render();});controls.append(before,after,smaller,larger);
   async function render(){
    if(rendering||!viewer.isConnected)return;rendering=true;for(const b of controls.children)b.disabled=true;
    try{const page=await pdf.getPage(pageNumber);if(!viewer.isConnected)return;const natural=page.getViewport({scale:1}),width=Math.max(160,Math.min(content.clientWidth,950)),scale=(width/natural.width)*zoom,viewport=page.getViewport({scale}),ratio=Math.min(window.devicePixelRatio||1,2,Math.sqrt(4000000/(viewport.width*viewport.height)),16000/Math.max(viewport.width,viewport.height));canvas.width=Math.ceil(viewport.width*ratio);canvas.height=Math.ceil(viewport.height*ratio);canvas.style.width=viewport.width+'px';canvas.style.height=viewport.height+'px';// PDF glyph positions use their own coordinates, independent of the surrounding interface direction.
    const canvasContext=canvas.getContext('2d');canvasContext.direction='ltr';canvasContext.textAlign='left';renderTask=page.render({canvasContext,viewport,transform:ratio===1?null:[ratio,0,0,ratio,0,0]});await renderTask.promise;if(viewer.isConnected)state.textContent=`صفحة ${pageNumber} من ${pdf.numPages}`;page.cleanup();}
    finally{rendering=false;before.disabled=pageNumber<=1;after.disabled=pageNumber>=pdf.numPages;smaller.disabled=zoom<=.5;larger.disabled=zoom>=2.5;}
   }
   await render();
  }else if(['image/png','image/jpeg','image/webp','image/gif'].includes(mime)){const image=document.createElement('img');image.alt=file.name;image.src=url;content.append(image);state.textContent='';}
  else if(mime==='text/plain'){const text=document.createElement('pre');text.textContent=await blob.text();content.append(text);state.textContent='';}
  else{tab.remove();state.textContent='المعاينة داخل النظام غير متاحة لهذا النوع من الملفات. يمكنك تنزيله لفتحه بالتطبيق المناسب.';}
 }catch(error){if(viewer.isConnected){state.textContent=error.message||'تعذر عرض المرفق. أغلق المعاينة وأعد المحاولة.';state.dataset.error='true';}}
 return viewer;
}
