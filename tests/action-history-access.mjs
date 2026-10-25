import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync('assets/js/tasks-page.js','utf8');
const code=source.slice(source.indexOf('function renderActivityLog('),source.indexOf('const taskMeasurementLinks=',source.indexOf('function renderActivityLog(')));
for(const role of ['admin','manager','employee']){
 const nodes=Object.fromEntries(['activityLogSection','activityLogList','activityLogSummary','activityLogToggle'].map(id=>[id,{innerHTML:'old private data',hidden:false,classList:{toggle(){}},replaceChildren(){this.innerHTML=''}}]));
 const context={currentProfile:{role},document:{getElementById:id=>nodes[id]},activityLogExpanded:false,normalizeActivity:()=>[{createdAt:1,detail:'private log'}],escapeHTML:String,activityIcon:()=>'',activityLabel:()=>'',formatActivityTime:()=>'',selectedTask:()=>({})};vm.createContext(context);vm.runInContext(code,context);context.renderActivityLog({});
 assert.equal(nodes.activityLogSection.hidden,role!=='admin');
 if(role!=='admin'){assert.equal(nodes.activityLogList.innerHTML,'');context.toggleActivityLog();assert.equal(context.activityLogExpanded,false)}else assert.match(nodes.activityLogList.innerHTML,/private log/);
}
console.log('PASS task action history: admin display, non-admin clearing and toggle denial');
