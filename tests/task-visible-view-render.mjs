import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const render=source.slice(source.indexOf('function renderTasks(){'),source.indexOf('function applyTaskFieldPermissions('));
const rows=Array.from({length:200},(_,i)=>({id:String(i),status:'قيد الانتظار',title:'Fixture'}));
for(const [mode,archive,expected] of [['KANBAN',false,0],['LIST',false,200],['KANBAN',true,200]]){
 let created=0,forwarded=0;const box={innerHTML:'',appendChild(){}};const count={textContent:''};
 const ctx=vm.createContext({document:{getElementById:id=>id==='tasksList'?box:id==='visibleCount'?count:{classList:{toggle(){}}},createElement:()=>{created++;return {dataset:{},querySelector:()=>({})}}},taskViewMode:mode,isCompletedArchiveView:()=>archive,tasks:rows,selectedTaskKey:null,currentProfile:{role:'admin'},setupAssigneeFilter(){},sortTasksForDisplay:r=>r,filteredTasks:()=>rows,calcDelay:()=>0,compositeKey:t=>t.id,isCurrentlyOverdue:()=>false,localDateISO:()=>'',calcDuration:()=>0,smartDate:()=>'',normalizeProgress:()=>0,escapeHTML:String,priorityLabel:String,renderKanban:r=>forwarded=r.length});
 vm.runInContext(render,ctx);ctx.renderTasks();assert.equal(created,expected);assert.equal(forwarded,200);assert.equal(count.textContent,'200 مهام');
}
const kanbanGuard=source.slice(source.indexOf('function renderKanban('),source.indexOf('  const isOverdue=',source.indexOf('function renderKanban(')))+'return "render";}';
let cleared=0;const ctx=vm.createContext({taskViewMode:'LIST',isCompletedArchiveView:()=>false,document:{getElementById:()=>({replaceChildren(){cleared++}})}});vm.runInContext(kanbanGuard,ctx);assert.equal(ctx.renderKanban(rows),undefined);assert.equal(cleared,1);ctx.taskViewMode='KANBAN';assert.equal(ctx.renderKanban(rows),'render');
const start=source.indexOf('function scrollSelectedTaskIntoView(');const scroll=source.slice(start,source.indexOf('\nfunction ',start+10));let scrolled=0;
const nav=vm.createContext({selectedTaskKey:'fixture',CSS:{escape:String},document:{querySelector:s=>s.includes('data-kanban-task')?{scrollIntoView(){scrolled++}}:null}});vm.runInContext(scroll,nav);nav.scrollSelectedTaskIntoView(false);assert.equal(scrolled,1);
console.log('PASS actual renderer: all 200 records retained; no hidden list cards in Kanban; no hidden board in List/archive; board selection scroll retained.');
