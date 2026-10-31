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
export function createRunControl(initialWidth){
 let reason=null;
 return {get reason(){return reason;},stop(next){reason??=next;},resize(width){if(Math.abs(width-initialWidth)>1)this.stop('viewport-changed');}};
}
export function stopMessage(reason){return ({'user-stop':'تم الضغط على زر الإيقاف','viewport-changed':'تغير عرض الصفحة أو اتجاه الهاتف؛ يلزم تشغيل مستقل بالمقاس الجديد',background:'انتقلت الصفحة إلى الخلفية',login:'جلسة الدخول غير متاحة',timeout:'انتهت مهلة تحميل الصفحة',error:'تعذر تحميل بيانات الصفحة','paint-timeout':'لم يكتمل إطار الرسم في المهلة المحددة','cross-origin':'انتقلت الصفحة إلى نطاق آخر','unexpected-error':'حدث خطأ غير متوقع'})[reason]||'تعذر إكمال القياس';}
if(typeof document!=='undefined'&&document.getElementById('probe')){
 const $=id=>document.getElementById(id),frame=$('probe');let running=false,run,report;
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
   if(run.reason)return {state:run.reason};
   if(document.hidden)return {state:'background'};
   let state='pending';
   try{const doc=frame.contentDocument;if(doc?.location.pathname===target.pathname)state=readiness(doc,page.key);else if(doc&&(/\/(?:login|trial-login|admin-login)\.html$/.test(doc.location.pathname)||doc.querySelector('input[type=password]')))state='login';}catch{return {state:'cross-origin'};}
   if(state==='ready'){
    const painted=await Promise.race([new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true)))),new Promise(resolve=>setTimeout(()=>resolve(false),2000))]);
    if(!painted)return {state:'paint-timeout'};
    if(run.reason||document.hidden)return {state:run.reason||'background'};
    return {state,ms:Math.round((performance.now()-navigationStart)*100)/100};
   }
   if(state!=='pending')return {state};
   await new Promise(resolve=>setTimeout(resolve,40));
  }
  return {state:'timeout'};
 }
 $('stop').onclick=()=>{run?.stop('user-stop');frame.src='about:blank';};
 $('start').onclick=async()=>{
  if(running)return;running=true;run=createRunControl(innerWidth);$('start').disabled=true;$('cohort').disabled=true;$('stop').disabled=false;$('download').disabled=true;
  report={schema:2,complete:false,interruptions:[],created_at:new Date().toISOString(),origin:location.origin,cohort:$('cohort').value,viewport:{width:innerWidth,height:innerHeight,frame_width:frame.clientWidth,frame_height:frame.clientHeight},protocol:'sequential natural-cache navigation (cache retention is not guaranteed), one excluded warm-up per route, 40ms readiness polling + two animation frames, 45s timeout; successful samples only; incomplete cohorts are not acceptance',pages:Object.fromEntries(pages.map(p=>[p.key,{samples:[],warmup:null}]))};render();
  const resized=()=>run.resize(innerWidth);addEventListener('resize',resized);
  try{
   for(const page of pages){
    $('status').textContent=`إحماء ${page.label}`;const result=await sample(page);report.pages[page.key].warmup=result;render();
    if(result.state!=='ready'){run.stop(result.state);break;}
    for(let i=0;i<30&&!run.reason;i++){
     $('status').textContent=`${page.label}: العينة ${i+1} من 30`;
     const result=await sample(page);
     if(['user-stop','viewport-changed','background'].includes(result.state))report.interruptions.push({page:page.key,state:result.state});
     else report.pages[page.key].samples.push(result);
     render();
     if(result.state!=='ready'){run.stop(result.state);break;}
     frame.src='about:blank';await new Promise(resolve=>setTimeout(resolve,700));
    }
    if(run.reason)break;
   }
   if(run.reason)report.stop_reason=run.reason;
   report.complete=pages.every(p=>summarize(report.pages[p.key].samples).complete);
   $('status').textContent=report.complete?'اكتمل القياس: 90 عينة ناجحة. هذه نتائج الجهاز والجلسة الحاليين فقط.':`توقف القياس: ${stopMessage(report.stop_reason)}. النتائج الجزئية ليست قبولًا نهائيًا.`;
  }catch{report.stop_reason='unexpected-error';$('status').textContent='تعذر إكمال القياس. النتائج الجزئية ليست قبولًا نهائيًا.';}
  finally{frame.src='about:blank';removeEventListener('resize',resized);running=false;$('start').disabled=false;$('cohort').disabled=false;$('stop').disabled=true;$('download').disabled=false;render();}
 };
 $('download').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='atwar-page-performance.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
}
