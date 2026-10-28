// Exercise the real policy editor; every backend read/write stays in memory.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--no-zygote','--single-process']});try{
 const page=await browser.newPage(),errors=[];page.setDefaultTimeout(12000);page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1'||/supabase-(config|runtime)|module-access|permissions\.js|session-service|supabase-firebase-compat/.test(u.pathname))return route.fulfill({body:'',contentType:'text/javascript'});const file=path.join(root,decodeURIComponent(u.pathname));if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return route.fulfill({status:404,body:''});return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.html')?'text/html':file.endsWith('.css')?'text/css':'text/javascript'});});
 await page.addInitScript(()=>{
  const me={id:'qa-admin',full_name:'اختبار',role:'admin',active:true,status:'active',allowed_modules:['policies']};
  const p={id:'qa-policy',code:'QA-POLICY',title:'سياسة اختبار',preparer_id:me.id,reviewer_id:'reviewer',revision:3,audience_groups:[],management_viewer_ids:[]};
  const v={id:'qa-version',policy_id:p.id,status:'PREPARATION',revision:7,version_number:1,version_label:'نسخة للمراجعة',content:[{body:'نص البند الأصلي',id:'purpose',title:'الغرض'}]};
  window.__state={v,calls:[],failSave:false};window.AtwarModules={allowed:()=>true,apply(){},require:async()=>true};
  localStorage.setItem('atwarSession',JSON.stringify(me));
  const result=table=>({data:structuredClone(table==='profiles'?[me]:table==='policies'?[p]:table==='policy_versions'?[v]:[]),error:null});
  const sb={auth:{getSession:async()=>({data:{session:{user:me}}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},from(table){const q=new Proxy({then(resolve){return Promise.resolve(result(table)).then(resolve)}},{get:(t,k)=>k in t?t[k]:()=>q});return q;},async rpc(name,args){if(name==='policy_directory'||name==='policy_people')return {data:[me],error:null};window.__state.calls.push({name,args});if(name==='policy_save'){if(window.__state.failSave)return {error:{message:'تعذر الحفظ التجريبي'}};if(args.p_revision!==v.revision)return {error:{message:'ATWAR_CONFLICT'}};v.content=args.p_content.map(s=>({body:s.body,id:s.id,title:s.title}));v.version_label=args.p_label;v.revision++;}else if(name==='policy_decide'){if(args.p_revision!==v.revision)return {error:{message:'ATWAR_CONFLICT'}};v.status='REVIEW';v.revision++;}return {data:null,error:null};}};
  window.atwarGetSupabase=async()=>sb;
 });
 const url='http://127.0.0.1:8765/policies/index.html?id=qa-policy';
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:900});await page.goto(url);await page.locator('#togglePolicyEdit').click();
  await page.locator('#togglePolicyEdit').click();assert.equal(await page.locator('#policyEdit').count(),0,'Unchanged JSONB content can switch to reading');
  await page.locator('#togglePolicyEdit').click();await page.locator('#policyDecision [name=note]').fill('جاهزة للمراجعة');
  await page.locator('#policyDecision button[value=advance]').click();await page.waitForFunction(()=>window.__state.v.status==='REVIEW');
  assert.equal((await page.evaluate(()=>window.__state.calls)).filter(x=>x.name==='policy_decide').length,1,'Unchanged editor can submit without a phantom save');
  await page.goto(url);await page.locator('#togglePolicyEdit').click();
  await page.locator('.section-body').fill('نص معدل');await page.locator('#policyDecision [name=note]').fill('جاهزة للمراجعة');await page.locator('#policyDecision button[value=advance]').click();
  await page.waitForFunction(()=>document.getElementById('policyMessage').textContent.includes('احفظ تعديلات'));
  assert.equal((await page.evaluate(()=>window.__state.calls.filter(x=>x.name==='policy_decide'))).length,0,'Unsaved content never reaches decision RPC');assert.equal(await page.locator('.section-body').inputValue(),'نص معدل');
  await page.locator('.section-body').fill('نص البند الأصلي');await page.locator('#policyEdit [name=label]').fill('تسمية معدلة');await page.locator('#togglePolicyEdit').click();assert.equal(await page.locator('#policyEdit').count(),1,'Label-only changes are protected');
  await page.locator('#policyDecision button[value=advance]').click();assert.equal((await page.evaluate(()=>window.__state.calls.filter(x=>x.name==='policy_decide'))).length,0,'Label-only change blocks submission');
  await page.evaluate(()=>window.__state.failSave=true);await page.locator('#policyEdit button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('policyMessage').textContent.includes('تعذر الحفظ التجريبي'));assert.equal(await page.locator('#policyEdit [name=label]').inputValue(),'تسمية معدلة','Failed save keeps edits');
  await page.evaluate(()=>window.__state.failSave=false);await page.locator('#policyEdit button[type=submit]').click();await page.waitForFunction(()=>window.__state.v.revision===8&&document.getElementById('policyMessage').textContent==='تم حفظ الإجراء.');
  await page.locator('#togglePolicyEdit').click();assert.equal(await page.locator('#policyEdit').count(),0,'Saved draft switches to reading');await page.locator('#togglePolicyEdit').click();
  await page.locator('#policyDecision [name=note]').fill('اعتماد الإرسال بعد الحفظ');await page.locator('#policyDecision button[value=advance]').click();await page.waitForFunction(()=>window.__state.v.status==='REVIEW');
  assert.equal((await page.evaluate(()=>window.__state.calls.find(x=>x.name==='policy_decide'))).args.p_revision,8,'Submission uses saved revision');
  assert.deepEqual(errors,[]);console.log('PASS policy editor: unchanged, content/label edits, save failure/retry and review submission',width);
 }
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
