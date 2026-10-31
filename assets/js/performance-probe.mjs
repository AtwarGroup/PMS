export const pages=[{key:'home',path:'home.html',label:'الرئيسية'},{key:'tasks',path:'tasks/index.html',label:'المهام'},{key:'workspace',path:'workspace/index.html',label:'مساحتي'}];
export function percentile(values,p){if(!values.length)return null;const a=[...values].sort((a,b)=>a-b);return Math.round(a[Math.max(0,Math.ceil(a.length*p)-1)]*100)/100;}
export function readiness(doc,key){
 if(!doc?.body)return 'pending';
 if(/\/(?:login|trial-login|admin-login)\.html$/.test(doc.location.pathname))return 'login';
 if(/\/(login|index)\.html$/.test(doc.location.pathname)&&!doc.querySelector('#appShell')&&key!=='tasks'&&doc.querySelector('input[type=password]'))return 'login';
 if(doc.querySelector('input[type=password]')&&!doc.querySelector('#appShell')&&key==='tasks')return 'login';
 if(key==='home'){
  const status=doc.querySelector('.atwar-data-status'),button=status?.querySelector('button');
  if(status&&button&&!button.disabled)return status.hidden?'ready':'error';
 }
 if(key==='tasks'){
  if(doc.querySelector('#loginScreen')&&!doc.querySelector('#loginScreen').classList.contains('hidden'))return 'login';
  const state=doc.documentElement.dataset.taskMeasureState;
  if(state==='error')return 'error';
  const shell=doc.querySelector('#appShell');
  if(state==='ready'&&shell&&!shell.classList.contains('hidden'))return 'ready';
  if(doc.querySelector('#authLoadingTitle')?.textContent.includes('تعذر'))return 'error';
 }
 if(key==='workspace'){
  const text=doc.querySelector('#spaceSync')?.textContent||'';
  if(text.startsWith('محدّث الآن'))return 'ready';
  if(text.includes('غير متاحة')||text.includes('تعذر'))return 'error';
 }
 return 'pending';
}
export function summarize(samples){const ok=samples.filter(s=>s.state==='ready').map(s=>s.ms);return {success:ok.length,failures:samples.length-ok.length,p50_ms:percentile(ok,.5),p95_ms:percentile(ok,.95),complete:ok.length===30};}
if(typeof document!=='undefined'&&document.getElementById('probe')){
 const $=id=>document.getElementById(id),frame=$('probe');let running=false,cancelled=false,report;
 const render=()=>{
  $('results').replaceChildren(...pages.map(page=>{const row=document.createElement('tr'),s=summarize(report.pages[page.key].samples);for(const value of [page.label,s.success,s.failures,s.p50_ms??'—',s.p95_ms??'—']){const td=document.createElement('td');td.textContent=value;row.append(td);}return row;}));
  $('report').textContent=JSON.stringify(report,null,2);
 };
 async function sample(page){
  const target=new URL('../'+page.path,location.href);target.searchParams.set('performance_probe','1');
  frame.src='about:blank';await new Promise(resolve=>setTimeout(resolve,50));
  // Start before assignment; all clock readings belong to the same parent document.
  const navigationStart=performance.now();frame.src=target.href;
  while(performance.now()-navigationStart<45000){
   if(cancelled)return {state:'cancelled'};
   if(document.hidden)return {state:'background'};
   let state='pending';
   try{const doc=frame.contentDocument;if(doc?.location.pathname===target.pathname)state=readiness(doc,page.key);else if(doc&&(/\/(?:login|trial-login|admin-login)\.html$/.test(doc.location.pathname)||doc.querySelector('input[type=password]')))state='login';}catch{return {state:'cross-origin'};}
   if(state==='ready'){
    const painted=await Promise.race([new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true)))),new Promise(resolve=>setTimeout(()=>resolve(false),2000))]);
    if(!painted)return {state:'paint-timeout'};
    if(cancelled||document.hidden)return {state:cancelled?'cancelled':'background'};
    return {state,ms:Math.round((performance.now()-navigationStart)*100)/100};
   }
   if(state!=='pending')return {state};
   await new Promise(resolve=>setTimeout(resolve,40));
  }
  return {state:'timeout'};
 }
 $('stop').onclick=()=>{cancelled=true;frame.src='about:blank';};
 $('start').onclick=async()=>{
  if(running)return;running=true;cancelled=false;$('start').disabled=true;$('cohort').disabled=true;$('stop').disabled=false;$('download').disabled=true;
  report={schema:1,created_at:new Date().toISOString(),origin:location.origin,cohort:$('cohort').value,viewport:{width:innerWidth,height:innerHeight,frame_width:frame.clientWidth,frame_height:frame.clientHeight},protocol:'sequential natural-cache navigation (cache retention is not guaranteed), one excluded warm-up per route, 40ms readiness polling + two animation frames, 45s timeout; successful samples only; incomplete cohorts are not acceptance',pages:Object.fromEntries(pages.map(p=>[p.key,{samples:[],warmup:null}]))};render();
  const resized=()=>{cancelled=true;report.stop_reason='viewport-changed';};addEventListener('resize',resized);
  try{
   for(const page of pages){
    $('status').textContent=`إحماء ${page.label}`;const result=await sample(page);report.pages[page.key].warmup=result;render();
    if(result.state!=='ready'){report.stop_reason=result.state;break;}
    for(let i=0;i<30&&!cancelled;i++){
     $('status').textContent=`${page.label}: العينة ${i+1} من 30`;
     const result=await sample(page);report.pages[page.key].samples.push(result);render();
     if(result.state!=='ready'){report.stop_reason=result.state;cancelled=true;break;}
     frame.src='about:blank';await new Promise(resolve=>setTimeout(resolve,700));
    }
    if(cancelled)break;
   }
   report.complete=pages.every(p=>summarize(report.pages[p.key].samples).complete);
   $('status').textContent=report.complete?'اكتمل القياس: 90 عينة ناجحة. هذه نتائج الجهاز والجلسة الحاليين فقط.':`توقف القياس: ${report.stop_reason||'إيقاف المستخدم'}. النتائج الجزئية ليست قبولًا نهائيًا.`;
  }catch{report.stop_reason='unexpected-error';$('status').textContent='تعذر إكمال القياس. النتائج الجزئية ليست قبولًا نهائيًا.';}
  finally{frame.src='about:blank';removeEventListener('resize',resized);running=false;$('start').disabled=false;$('cohort').disabled=false;$('stop').disabled=true;$('download').disabled=false;render();}
 };
 $('download').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='atwar-page-performance.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
}
