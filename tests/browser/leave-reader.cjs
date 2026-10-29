// Exercise the real policy editor; every backend read/write stays in memory.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process']});try{
 const page=await browser.newPage(),errors=[];page.setDefaultTimeout(12000);page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1'||/supabase-(config|runtime)|module-access|permissions\.js|session-service|supabase-firebase-compat/.test(u.pathname))return route.fulfill({body:'',contentType:'text/javascript'});const file=path.join(root,decodeURIComponent(u.pathname));if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return route.fulfill({status:404,body:''});return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.html')?'text/html':file.endsWith('.css')?'text/css':'text/javascript'});});
 await page.addInitScript(()=>{
  const me={id:'qa-admin',full_name:'اختبار',role:'admin',active:true,status:'active',allowed_modules:['policies']};
  const p={id:'qa-policy',code:'POL-LEAVE',title:'سياسة الإجازات والتذاكر',preparer_id:me.id,reviewer_id:'reviewer',revision:3,audience_groups:[],management_viewer_ids:[]};
  const v={id:'qa-version',policy_id:p.id,status:'PREPARATION',revision:7,version_number:1,version_label:'V2.2 — للمراجعة والاعتماد',content:Array.from({length:30},(_,i)=>({id:'leave-section-'+(i+1),title:i<27?(i+1)+' بند السياسة':'الملحق '+(i-26),body:i===29?'| الجنسية | قيمة البدل |\n| --- | --- |\n| مصر | 900 |\n| اليمن | 2000 |':i===27?'| الإجراء | الموظف | المدير | الموارد البشرية | الرئيس التنفيذي |\n| --- | --- | --- | --- | --- |\n| تعديل الإجازة | يقدم الطلب | يراجع | يتحقق | يعتمد الاستثناء |':'نص القسم '+(i+1)}))};
  window.__state={v,calls:[],failSave:false};window.AtwarModules={allowed:()=>true,apply(){},require:async()=>true};
  localStorage.setItem('atwarSession',JSON.stringify(me));
  const result=table=>({data:structuredClone(table==='profiles'?[me]:table==='policies'?[p]:table==='policy_versions'?[v]:[]),error:null});
  const sb={auth:{getSession:async()=>({data:{session:{user:me}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},from(table){const q=new Proxy({then(resolve){return Promise.resolve(result(table)).then(resolve)}},{get:(t,k)=>k in t?t[k]:()=>q});return q;},async rpc(name,args){if(name==='policy_directory'||name==='policy_people')return {data:[me],error:null};window.__state.calls.push({name,args});if(name==='policy_save'){if(window.__state.failSave)return {error:{message:'تعذر الحفظ التجريبي'}};if(args.p_revision!==v.revision)return {error:{message:'ATWAR_CONFLICT'}};v.content=args.p_content.map(s=>({body:s.body,id:s.id,title:s.title}));v.version_label=args.p_label;v.revision++;}else if(name==='policy_decide'){if(args.p_revision!==v.revision)return {error:{message:'ATWAR_CONFLICT'}};v.status='REVIEW';v.revision++;}return {data:null,error:null};}};
  window.atwarGetSupabase=async()=>sb;
 });

 const url='http://127.0.0.1:8765/policies/index.html?id=qa-policy';
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:900});await page.goto(url);
  await page.locator('#travelSearch').waitFor();
  assert.equal(await page.locator('[data-travel-panel]').count(),30);
  assert.equal(await page.locator('[data-travel-target]').count(),30);
  assert.equal(await page.locator('.travel-index nav>details').count(),7);
  assert.equal(await page.locator('.policy-leave-reader').count(),1);
  assert.equal(await page.locator('.policy-data-table colgroup').count(),0);
  assert.equal(await page.locator('#policyViewMode').count(),0);
  const original=await page.evaluate(()=>JSON.stringify(window.__state.v.content));
  await page.locator('#travelSearch').fill('٢٠٠٠');
  await page.locator('#travelResults button').first().click();
  assert.equal(await page.locator('[data-travel-panel="leave-section-30"]').getAttribute('open'),'');
  assert(await page.locator('mark.travel-match').evaluateAll(els=>els.some(el=>el.getClientRects().length)));
  await page.locator('#travelClear').click();
  await page.locator('[data-travel-target="leave-section-28"]').evaluate(el=>el.closest('details').open=true);
  await page.locator('[data-travel-target="leave-section-28"]').click();
  assert.equal(await page.locator('[data-travel-panel="leave-section-28"] th').count(),5);
  await page.locator('#travelCollapse').click();
  assert.equal(await page.locator('[data-travel-panel][open]').count(),0);
  await page.evaluate(()=>window.dispatchEvent(new Event('beforeprint')));
  assert.equal(await page.locator('[data-travel-panel][open]').count(),30);
  await page.evaluate(()=>window.dispatchEvent(new Event('afterprint')));
  assert.equal(await page.locator('[data-travel-panel][open]').count(),0);
  await page.locator('#travelExpand').click();
  assert.equal(await page.locator('[data-travel-panel][open]').count(),30);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'No page-level horizontal overflow');
  assert.equal(await page.evaluate(()=>JSON.stringify(window.__state.v.content)),original,'Reading and search never change stored content');
  assert.deepEqual((await page.evaluate(()=>window.__state.calls)).filter(call=>call.name!=='presence_ping'),[],'Only the expected shell presence heartbeat is allowed; no policy write RPCs');
  assert.deepEqual(errors,[]);
  console.log('PASS leave reader: 30 sections, grouped index, ticket table search, authority matrix, print restore and mobile layout',width);
 }
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});

