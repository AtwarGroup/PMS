import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(new URL('..',import.meta.url).pathname);
const css=fs.readFileSync(path.join(root,'assets/css/shared.css'),'utf8');
const required=['ATWAR ONE V0.32 — STABILIZATION DESIGN SYSTEM','--atwar-control-height:40px','--atwar-dialog-width:520px','.dialog-backdrop','.password-dialog','.workspace-shell',':focus-visible','@media(max-width:560px)'];
for(const token of required)if(!css.includes(token))throw new Error(`Missing unified design token: ${token}`);
const htmlFiles=[];
function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){if(['.git','node_modules','tmp'].includes(entry.name))continue;const full=path.join(dir,entry.name);if(entry.isDirectory())walk(full);else if(entry.name.endsWith('.html'))htmlFiles.push(full)}}
walk(root);
const shellPages=htmlFiles.filter(file=>fs.readFileSync(file,'utf8').includes('atwar-shell'));
const missing=shellPages.filter(file=>!fs.readFileSync(file,'utf8').includes('assets/css/shared.css'));
if(missing.length)throw new Error(`Shell pages missing shared.css: ${missing.map(x=>path.relative(root,x)).join(', ')}`);
const taskPages=['tasks/index.html','tasks/executive.html','recurring/index.html'].map(file=>fs.readFileSync(path.join(root,file),'utf8'));
for(const page of taskPages){
  if(!page.includes('task-suite-page')||!page.includes('task-suite-hero'))throw new Error('A task-suite page is missing the unified page and hero contract');
}
const taskIndex=taskPages[0];
if(!taskIndex.includes('listViewButton')||!taskIndex.includes('kanbanViewButton'))throw new Error('Task workspace must retain both list and Kanban views');
if(!taskIndex.includes('body.atwar-kanban-mode #kanbanView{overflow:visible}'))throw new Error('Task Kanban must not use a cramped internal vertical scroller');
if(!fs.readFileSync(path.join(root,'assets/js/tasks-page.js'),'utf8').includes('managerDashboardCollapsed=true'))throw new Error('Team overview must start in a compact state');
if(!taskIndex.includes('#managerDashboard.manager-dashboard-collapsed{width:max-content'))throw new Error('Collapsed team overview must not remain a full-width bar');
for(const label of ['مكتملة هذا الشهر','مكتملة في الموعد','مكتملة بعد الموعد','متوسط مدة الإنجاز']){
  if(!fs.readFileSync(path.join(root,'assets/js/tasks-page.js'),'utf8').includes(label))throw new Error(`Completed archive metric is missing: ${label}`);
}
if(!taskPages[2].includes('بيانات المهمة')||!taskPages[2].includes('إعدادات التكرار'))throw new Error('Recurring task form must be split into clear sections');
for(const insight of ['الأكثر تأخراً','الأعلى إنجازاً','يحتاجون متابعة','بانتظار الاعتماد'])if(!taskPages[1].includes(insight))throw new Error(`Executive insight is missing: ${insight}`);
if(!taskPages[1].includes('grid-template-columns:repeat(4,minmax(245px,1fr))'))throw new Error('Executive Kanban must use four readable active-work columns');
if(!taskPages[1].includes('.executive-table-wrap{overflow-x:auto;overflow-y:visible}'))throw new Error('Executive list must not have an internal vertical scrollbar');
for(const tone of ['row-waiting','row-progress','row-approval','row-overdue','row-completed'])if(!taskPages[1].includes(tone))throw new Error(`Executive list is missing the shared status tone: ${tone}`);
if(!taskPages[1].includes('grid-template-columns:minmax(240px,380px) 210px 180px'))throw new Error('Executive search and filters must use restrained control widths');
const shell=fs.readFileSync(path.join(root,'assets/js/shell-components.js'),'utf8');
for(const label of ['النشطة','المكتملة','الدورية','الاطلاع التنفيذي'])if(!shell.includes(label))throw new Error(`Missing task-suite navigation item: ${label}`);
console.log(`Unified UI design-system audit passed: ${shellPages.length} authenticated pages.`);
