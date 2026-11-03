import {fleetFile} from './fleet-file-storage.mjs?v=2.8.0';
// Preview uses the same protected read as downloading, without a public file URL.
export async function openFleetAttachment(rpc,id,kind='request'){
 const previous=document.activeElement,viewer=document.createElement('dialog');viewer.className='fleet-attachment-viewer';viewer.setAttribute('aria-label','معاينة المرفق');
 const header=document.createElement('header'),title=document.createElement('h2'),close=document.createElement('button');title.textContent='معاينة المرفق';close.type='button';close.className='fleet-btn secondary';close.textContent='إغلاق المعاينة';header.append(title,close);
 const state=document.createElement('p');state.setAttribute('role','status');state.textContent='جارٍ تحميل المعاينة…';
 const content=document.createElement('div');content.className='fleet-attachment-content';const actions=document.createElement('div');actions.className='fleet-action-buttons';viewer.append(header,state,actions,content);document.body.append(viewer);
 let url=null,pdfTask=null,renderTask=null;close.onclick=()=>viewer.close();viewer.addEventListener('close',()=>{if(url)URL.revokeObjectURL(url);renderTask?.cancel();void pdfTask?.destroy();viewer.remove();if(previous?.isConnected)previous.focus();},{once:true});viewer.showModal();
 try{
  const file=await fleetFile(rpc,id,kind);if(!viewer.isConnected)return;
  if(!['application/pdf','image/png','image/jpeg'].includes(file.mime))throw Error('نوع المرفق لا يدعم المعاينة.');
  const bytes=Uint8Array.from(atob(file.base64.replace(/\s/g,'')),c=>c.charCodeAt(0));url=URL.createObjectURL(new Blob([bytes],{type:file.mime}));title.textContent=file.name;
  const download=document.createElement('a');download.className='fleet-btn secondary';download.textContent='تنزيل';download.href=url;download.download=file.name;
  const tab=document.createElement('a');tab.className='fleet-btn secondary';tab.textContent='فتح في تبويب جديد';tab.href=url;tab.target='_blank';tab.rel='noopener noreferrer';actions.append(download,tab);
  if(file.mime==='application/pdf'){
   state.textContent='جارٍ تجهيز صفحات PDF…';
   const pdfjs=await import('../vendor/pdfjs-6.5.438/build/pdf.min.mjs');if(!viewer.isConnected)return;
   const base=new URL('../vendor/pdfjs-6.5.438/',import.meta.url);pdfjs.GlobalWorkerOptions.workerSrc=new URL('build/pdf.worker.min.mjs',base).href;
   pdfTask=pdfjs.getDocument({data:bytes,cMapUrl:new URL('cmaps/',base).href,cMapPacked:true,standardFontDataUrl:new URL('standard_fonts/',base).href,wasmUrl:new URL('wasm/',base).href,iccUrl:new URL('iccs/',base).href,disableWorkerRendering:true,enableXfa:false});
   const pdf=await pdfTask.promise;if(!viewer.isConnected)return;
   const controls=document.createElement('div');controls.className='fleet-pdf-controls';const canvas=document.createElement('canvas');canvas.setAttribute('role','img');canvas.setAttribute('aria-label','صفحة من ملف '+file.name);content.append(controls,canvas);
   let pageNumber=1,zoom=1,rendering=false;
   const button=(label,action)=>{const b=document.createElement('button');b.type='button';b.className='fleet-btn secondary';b.textContent=label;b.onclick=()=>action().catch(error=>{if(viewer.isConnected)state.textContent='تعذر عرض الصفحة: '+error.message;});return b;};
   const before=button('الصفحة السابقة',async()=>{pageNumber--;await render();}),after=button('الصفحة التالية',async()=>{pageNumber++;await render();}),smaller=button('تصغير',async()=>{zoom=Math.max(.5,zoom-.25);await render();}),larger=button('تكبير',async()=>{zoom=Math.min(2.5,zoom+.25);await render();});controls.append(before,after,smaller,larger);
   async function render(){
    if(rendering||!viewer.isConnected)return;rendering=true;for(const b of controls.children)b.disabled=true;
    try{const page=await pdf.getPage(pageNumber);if(!viewer.isConnected)return;const natural=page.getViewport({scale:1}),width=Math.max(160,Math.min(content.clientWidth,950)),scale=(width/natural.width)*zoom,viewport=page.getViewport({scale}),ratio=Math.min(window.devicePixelRatio||1,2,Math.sqrt(4000000/(viewport.width*viewport.height)),16000/Math.max(viewport.width,viewport.height));canvas.width=Math.ceil(viewport.width*ratio);canvas.height=Math.ceil(viewport.height*ratio);canvas.style.width=viewport.width+'px';canvas.style.height=viewport.height+'px';renderTask=page.render({canvasContext:canvas.getContext('2d'),viewport,transform:ratio===1?null:[ratio,0,0,ratio,0,0]});await renderTask.promise;if(viewer.isConnected)state.textContent=`صفحة ${pageNumber} من ${pdf.numPages}`;page.cleanup();}
    finally{rendering=false;before.disabled=pageNumber<=1;after.disabled=pageNumber>=pdf.numPages;smaller.disabled=zoom<=.5;larger.disabled=zoom>=2.5;}
   }
   await render();
  }else{const image=document.createElement('img');image.alt=file.name;image.src=url;content.append(image);state.textContent='';}
 }catch(error){if(viewer.isConnected){state.textContent=error.message||'تعذر عرض المرفق. أغلق المعاينة وأعد المحاولة.';state.dataset.error='true';}}
 return viewer;
}
