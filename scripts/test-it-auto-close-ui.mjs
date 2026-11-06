import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
import {createITTestDB} from './it-support-test-db.mjs';
import {archived} from '../assets/js/it-support-model.mjs';
const {db,rpc,create,detail,action,ids}=await createITTestDB();let browser,server;
try{
 await db.exec(await readFile('supabase/migrations/20261106220359_it_support_business_hour_auto_close.sql','utf8'));
 const id=await create();await action(ids.fleet,id,'resolve',{note:'تم إصلاح الاتصال وإعادة تشغيل الجهاز'});
 const root=resolve('.');server=createServer(async(req,res)=>{try{const p=resolve(root,'.'+new URL(req.url,'http://local').pathname);if(!p.startsWith(root+'/'))throw Error();const body=await readFile(p);res.setHeader('Content-Type',({'.html':'text/html','.mjs':'text/javascript','.js':'text/javascript','.css':'text/css'})[extname(p)]||'application/octet-stream');res.end(body);}catch{res.writeHead(404);res.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const p=await browser.newPage({viewport:{width:390,height:844}}),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.route('**/*',r=>{const u=new URL(r.request().url());if(u.origin!==base)return r.abort();if(u.pathname.endsWith('.js'))return r.fulfill({body:'',contentType:'text/javascript'});return r.continue();});
 await p.exposeFunction('qaRpc',async(name,args={})=>{const a=({it_support_context:[],it_support_list:[],it_support_detail:[args.p_id],it_support_action:[args.p_id,args.p_revision,args.p_action,JSON.stringify(args.p_data)]})[name];if(!a)throw Error('Unexpected RPC '+name);try{return {data:await rpc(ids.driver,name,a),error:null};}catch(e){return{data:null,error:{message:e.message}};}});
 await p.addInitScript(()=>{window.AtwarSession={require:async()=>true};window.atwarGetSupabase=async()=>({rpc:(...args)=>window.qaRpc(...args)});});
 await p.goto(base+'/it-support/index.html?request='+id);await expect(p.locator('[aria-label="مهلة تأكيد الحل"]')).toContainText('48 ساعة عمل');await expect(p.locator('[aria-label="مهلة تأكيد الحل"]')).toContainText('السبت إلى الخميس');await expect(p.locator('#requestAction option[value=reopen]')).toHaveText('المشكلة لم تُحل');
 for(const width of [320,390,1280]){await p.setViewportSize({width,height:844});assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false);}
 await p.locator('#requestAction').selectOption('reopen');await p.locator('#replyForm [name=note]').fill('ما زال انقطاع الاتصال مستمرًا');await p.locator('#sendRequestAction').click();await expect(p.locator('[aria-label="مهلة تأكيد الحل"]')).toHaveCount(0);assert.equal((await detail(id)).ticket.auto_close_at,null);
 await action(ids.fleet,id,'resolve',{note:'تمت معالجة المشكلة بعد التجربة الثانية'});await db.query("update private.it_support_tickets set auto_close_at=now()-interval '1 second'where id=$1",[id]);await db.query('select private.it_support_solution_reminders()');await p.reload();await expect(p.locator('[aria-label="إغلاق تلقائي"]')).toBeVisible();await expect(p.locator('#requestAction')).toHaveValue('reopen');const closed=(await detail(id)).ticket;assert.equal(closed.rating,null);const closedAt=Date.parse(closed.auto_closed_at);assert.equal(archived(closed,closedAt+7*86400000-1),false);assert.equal(archived({...closed,updated_at:new Date(closedAt+8*86400000).toISOString()},closedAt+7*86400000),true);assert.deepEqual(errors,[]);console.log('PASS actual mobile support page: deadline/workweek, reopen cancels timer, automatic closure transcript and reopen option, no rating and seven-day archive.');
}finally{await browser?.close();if(server)await new Promise(r=>server.close(r));await db.close();}
