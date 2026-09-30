import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const read=p=>readFileSync(new URL(`../${p}`,import.meta.url),'utf8');
const source=stripTypeScriptTypes(read('supabase/functions/send-job-acknowledgement/index.ts'));
const id='00000000-0000-4000-8000-000000000001';
const pdfBase64=Buffer.from('%PDF'+'.'.repeat(150)).toString('base64');
async function scenario({status='pending',role='admin',claimed=true,storage=true,adminResend=true,foreign=false}={}){
 let handler;const calls=[];let sentBody;
 const row={id,profile_id:'employee',email_status:status,employee_email_snapshot:'employee@example.test',manager_email_snapshot:'manager@example.test',employee_name_snapshot:'QA',job_revision:1,job_snapshot:{title:'QA'},accepted_at:'2026-09-30T12:00:00Z'};
 const json=data=>new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
 const context={Deno:{env:{get:()=> 'test'},serve:fn=>handler=fn},Response,TextDecoder,Uint8Array,atob,crypto:webcrypto,Intl,Date,fetch:async(url,init={})=>{
  calls.push({url,method:init.method||'GET',body:init.body});
  if(url.includes('/auth/v1/user'))return json({id:foreign?'another':'employee'});
  if(url.includes('/rest/v1/profiles?'))return json([{role}]);
  if(url.includes('/rest/v1/job_description_acknowledgements?')){
   if(init.method==='PATCH')return json(url.includes('email_status=in.')?(claimed?[row]:[]):[row]);
   return json(foreign&&!adminResend?[]:[row]);
  }
  if(url.includes('/storage/v1/'))return new Response(storage?'ok':'failed',{status:storage?200:500});
  if(url==='https://api.resend.com/emails'){sentBody=JSON.parse(init.body);return json({id:'provider-message'});}
  throw Error('Unexpected URL');
 }};
 vm.runInNewContext(source,context);
 const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({acknowledgementId:id,pdfBase64,adminResend})}));
 return {response,calls,sentBody};
}
for(const status of ['pending','failed']){
 const s=await scenario({status});assert.equal(s.response.status,200);assert.ok(s.calls.some(c=>c.url.includes('email_status=in.(pending,failed)')));assert.ok(s.sentBody.attachments[0].content);assert.equal(s.sentBody.cc.length,2);assert.doesNotMatch(s.sentBody.subject,/نسخة مصححة/);assert.equal(s.calls.filter(c=>c.url==='https://api.resend.com/emails').length,1);
}
const denied=await scenario({role:'manager'});assert.equal(denied.response.status,403);assert.equal(denied.sentBody,undefined);
const busy=await scenario({status:'processing'});assert.equal(busy.response.status,409);assert.equal(busy.sentBody,undefined);
const lostClaim=await scenario({claimed:false});assert.equal(lostClaim.response.status,409);assert.equal(lostClaim.sentBody,undefined);
const sent=await scenario({status:'sent'});assert.equal(sent.response.status,200);assert.match(sent.sentBody.subject,/نسخة مصححة/);assert.ok(!sent.calls.some(c=>c.url.includes('email_status=in.')));
const ownReplay=await scenario({status:'sent',adminResend:false});assert.equal(ownReplay.response.status,200);assert.equal(ownReplay.sentBody,undefined);
const other=await scenario({adminResend:false,foreign:true});assert.equal(other.response.status,404);assert.equal(other.sentBody,undefined);
const failed=await scenario({storage:false});assert.equal(failed.response.status,500);assert.ok(failed.calls.some(c=>c.method==='PATCH'&&String(c.body).includes('"email_status":"failed"')));assert.equal(failed.sentBody,undefined);

const page=read('assets/js/job-library-page.js');
const render=page.slice(page.indexOf('function renderAssignments()'),page.indexOf('async function makeAdminAckPdf'));
function renderRow({status='pending',role='admin',revision=2,ackRevision=2,ackJob='job'}={}){
 const nodes={employeeSearch:{value:''},assignmentFilter:{value:''},assignmentList:{innerHTML:''}};
 vm.runInNewContext(render+';renderAssignments();',{normalizeArabic:x=>x,esc:x=>x??'',el:id=>nodes[id],me:{role},users:[{id:'employee',role:'employee',full_name:'QA'}],jobs:[{id:'job',title:'QA',revision,published_snapshot:{revision}}],assignments:[{profile_id:'employee',job_description_id:'job'}],acknowledgements:[{id,profile_id:'employee',job_description_id:ackJob,job_revision:ackRevision,email_status:status}],document:{querySelectorAll:()=>[]},saveAssignment:()=>{},resendAcknowledgement:()=>{}});
 return nodes.assignmentList.innerHTML;
}
assert.match(renderRow(),/استكمال إرسال الإقرار/);
assert.match(renderRow({status:'failed'}),/استكمال إرسال الإقرار/);
assert.match(renderRow({status:'sent'}),/إعادة إرسال الإقرار/);
for(const options of [{status:'processing'},{role:'manager'},{ackRevision:1},{ackJob:'old-job'}])assert.doesNotMatch(renderRow(options),/data-resend-ack/);
console.log('Acknowledgement recovery: authorization, atomic claim, PDF/CC, replay, failures and current-assignment UI passed.');
