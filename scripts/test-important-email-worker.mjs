import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {transform} from 'esbuild';
const {code}=await transform(await readFile(new URL('../supabase/functions/send-important-emails/index.ts',import.meta.url),'utf8'),{loader:'ts',format:'esm'});
let handler,mode='send',claims=0,sends=0,finishes=[],calls=[],statusCode=200;
const batch={batch_id:'b1',claim_token:'lease1',recipient:'test@example.test',items:[{payload:{subject:'طلب <اختبار>',summary:'محتوى <script>غير موثوق</script>',phase:'initial',due_at:'2026-11-03',path:'/fleet/index.html?request=test'}}]};
const context={Deno:{env:{get:k=>({SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'service',RESEND_API_KEY:'resend'}[k])},serve:f=>handler=f},Request,Response,AbortSignal,console,fetch:async(u,opts)=>{
 calls.push(u);
 if(u.endsWith('/important_email_claim')){const args=JSON.parse(opts.body);if(args.p_probe)return Response.json({ready:true,enabled:true});return Response.json(claims++===0?batch:{items:[]});}
 if(u.endsWith('/important_email_validate'))return Response.json(mode!=='stale');
 if(u.endsWith('/important_email_finish')){finishes.push(JSON.parse(opts.body));return new Response('null');}
 if(u==='https://api.resend.com/emails'){sends++;const mail=JSON.parse(opts.body);assert.deepEqual(mail.to,['test@example.test']);assert.equal(opts.headers['Idempotency-Key'],'important-action/b1');assert(mail.html.includes('&lt;script&gt;'));assert(!mail.html.includes('<script>'));assert(mail.text.includes('https://one.atwargroup.com/fleet/'));return Response.json(statusCode===200?{id:'provider1'}:{message:'rejected'},{status:statusCode});}
 throw Error('Unexpected request '+u);
}};
vm.runInNewContext(code,context);
const req=(body={})=>new Request('https://fn.example',{method:'POST',headers:{'x-atwar-worker':'a'.repeat(64),'Content-Type':'application/json'},body:JSON.stringify(body)});
assert.equal((await handler(new Request('https://fn.example',{method:'POST'}))).status,401);assert.equal(calls.length,0);
assert.equal((await handler(req({probe:true}))).status,200);assert.equal(sends,0);assert.equal(claims,0);
await handler(req());assert.equal(sends,1);assert.equal(finishes[0].p_provider,'provider1');
mode='stale';claims=0;await handler(req());assert.equal(sends,1,'stale mail sent');
mode='send';claims=0;statusCode=429;await handler(req());assert.equal(finishes.at(-1).p_retry,true);
claims=0;statusCode=422;await handler(req());assert.equal(finishes.at(-1).p_retry,false);
console.log('PASS important email worker: anonymous denial, probe without send, escaped RTL/text, fixed app links, idempotency, stale cancellation, retry and permanent failures');
