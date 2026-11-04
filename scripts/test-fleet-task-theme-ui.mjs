import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {chromium,expect} from '@playwright/test';
import {startPreview} from './fleet-preview.mjs';
import {ids} from './fleet-test-db.mjs';
const app=await startPreview();let browser;
try{
 const car=(await app.rpc('driver','fleet_snapshot')).vehicles[0];
 const titles=['طلب صيانة للمراجعة والمتابعة','طلب صيانة متأخر عن الموعد','طلب صيانة مكتمل'];
 for(const [i,state] of ['manager_review','repair','closed'].entries())await app.db.query("insert into private.fleet_requests(driver_id,vehicle_id,accountant_id,manager_id,description,fault_notes,request_type,maintenance_kind,odometer,state,state_changed_at,closed_at)values($1,$2,$3,$4,$5,'تفاصيل اختبار محلي لتوحيد الثيم','repair','tire',12510,$6,case when $6='repair' then now()-interval '10 days' else now() end,case when $6='closed' then now() else null end)",[ids.driver,car.id,ids.accountant,ids.manager,titles[i],state]);
 browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const fleet=await browser.newPage(),task=await browser.newPage(),errors=[];for(const p of [fleet,task]){p.on('pageerror',e=>errors.push(e.message));await p.route('**/*',r=>r.request().url().startsWith(app.url)?r.continue():r.abort());}
 let taskHTML=(await readFile(new URL('../tasks/index.html',import.meta.url),'utf8')).replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'');
 await task.route(app.url+'/tasks/index.html',r=>r.fulfill({body:taskHTML,contentType:'text/html'}));
 const source=await readFile(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');const renderer=source.slice(source.indexOf('function renderTasks(){'),source.indexOf('function applyTaskFieldPermissions('));assert(renderer.includes('task-list-row'));
 await task.goto(app.url+'/tasks/index.html');await task.addStyleTag({url:app.url+'/assets/css/shared.css'});await task.addStyleTag({url:app.url+'/assets/css/app-theme.css'});await task.addStyleTag({url:app.url+'/assets/css/typography.css'});await task.addStyleTag({url:app.url+'/assets/css/task-list-theme.css?v=20261104.1'});
 await task.addStyleTag({content:'.task-theme-reference{margin-inline-end:200px!important;padding:24px!important;width:auto!important}.task-theme-reference .task-suite-page{padding:0;max-width:none}@media(max-width:768px){.task-theme-reference{margin-inline-end:0!important;padding:16px!important}}'});
 await task.evaluate(({renderer,titles})=>{
  const filter=document.querySelector('.task-filter-bar'),panel=document.getElementById('taskListPanel'),root=document.createElement('div'),main=document.createElement('main');root.className='atwar-main task-theme-reference';main.className='task-suite-page';main.append(filter,panel);root.append(main);document.body.replaceChildren(root);document.getElementById('quickAddBox').style.display='none';
  const setup=`const tasks=${JSON.stringify(titles.map((title,i)=>({title,status:['بانتظار الاعتماد','قيد التنفيذ','مكتملة'][i],assign:'السائق التجريبي',priority:'normal',start:'2026-11-01',end:'2026-11-04',progress:50,attachments:[]})))};let selectedTaskKey=null,pendingAssigneeChange=null,transientSelectedTask=null;const reschedulesLoaded=false,taskViewMode='LIST',currentProfile={role:'admin'};const filteredTasks=()=>tasks,sortTasksForDisplay=x=>x,calcDelay=()=>0,compositeKey=t=>t.title,isCurrentlyOverdue=()=>false,isCompletedArchiveView=()=>false,smartDate=x=>x,normalizeProgress=x=>x,taskRescheduleBadge=()=>'',priorityLabel=()=>'',calcDuration=()=>3,localDateISO=()=>"2026-11-04",renderKanban=()=>{},setupAssigneeFilter=()=>{},escapeHTML=s=>String(s);`;
  new Function(setup+renderer+';renderTasks();')();
 },{renderer,titles});
 await fleet.goto(app.url+'/fleet/index.html?qa=driver');await expect(fleet.locator('#fleetStatus')).toHaveText('');await expect(fleet.locator('#fleetWorkRows article')).toHaveCount(3);
 const styles=async(p,base)=>p.locator(base).first().evaluate(row=>{const pick=(e,props)=>Object.fromEntries(props.map(k=>[k,getComputedStyle(e)[k]]));return{row:pick(row,['paddingTop','paddingBottom','paddingLeft','paddingRight','borderRadius']),title:pick(row.querySelector('.task-title-line'),['fontFamily','fontSize','fontWeight','lineHeight']),meta:pick(row.querySelector('.task-secondary'),['fontSize','lineHeight','columnGap','rowGap','marginTop']),operation:pick(row.querySelector('.task-operational'),['fontSize','lineHeight','columnGap','marginTop','paddingTop'])};});
 await mkdir('test-results',{recursive:true});
 for(const width of [1440,390,320]){
  for(const p of [fleet,task])await p.setViewportSize({width,height:1000});
  assert.deepEqual(await styles(fleet,'#fleetWorkRows article:not(.is-overdue):not(.is-completed)'),await styles(task,'#tasksList .task-card:not(.is-completed)'),'Shared row scale at '+width);
  for(const p of [fleet,task])assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2),false,'Overflow at '+width);
  const controls=await fleet.locator('[data-work-quick=all]').evaluate(e=>({height:e.getBoundingClientRect().height,font:getComputedStyle(e).fontSize}));const reference=await task.locator('#quickFilters .qf').first().evaluate(e=>({height:e.getBoundingClientRect().height,font:getComputedStyle(e).fontSize}));assert.deepEqual(controls,reference,'Shared quick filters at '+width);
  if(width!==320){await fleet.screenshot({path:`test-results/fleet-task-theme-${width}.png`,fullPage:true});await task.screenshot({path:`test-results/tasks-reference-${width}.png`,fullPage:true});}
 }
 await fleet.locator('[data-work-quick=overdue]').click();await expect(fleet.locator('#fleetWorkRows article')).toHaveCount(1);await expect(fleet.locator('#fleetWorkRows')).toContainText('التأخير:');await fleet.locator('[data-work-quick=all]').click();await fleet.locator('#workSearch').fill(titles[0]);await expect(fleet.locator('#fleetWorkRows article')).toHaveCount(1);await fleet.locator('#workKanbanView').click();await expect(fleet.locator('.kanban-column')).toHaveCount(5);await fleet.locator('#workListView').click();await fleet.locator('#fleetWorkRows').getByRole('button',{name:'عرض الطلب',exact:true}).click();await expect(fleet.locator('#fleetDialog')).toBeVisible();await expect(fleet.locator('#dialogBody')).toContainText(titles[0]);await fleet.locator('#closeDialog').click();await fleet.getByRole('link',{name:'الطلبات المكتملة والمنتهية',exact:true}).click();await expect(fleet.locator('#fleetWorkRows article')).toHaveCount(1);assert.deepEqual(errors,[]);
 console.log('PASS shared task/fleet production row typography, spacing and filters at 1440/390/320px; overdue/search/list/Kanban/open/archive preserved.');
}finally{await browser?.close();await app.close();}
