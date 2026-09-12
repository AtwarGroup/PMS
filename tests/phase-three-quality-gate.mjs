import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const taskHtml=read('tasks/index.html');
const taskPage=read('assets/js/tasks-page.js');
const failures=[];

// Every function called by inline task-page handlers must be exposed from the ES module.
const handlerAttributes=[...taskHtml.matchAll(/\son(?:click|change|input|keydown)=["']([^"']+)["']/gi)]
  .map(match=>match[1]);
const ignored=new Set(['if','reload','getElementById']);
const handlerNames=new Set();
for(const body of handlerAttributes){
  for(const match of body.matchAll(/(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(/g)){
    if(!ignored.has(match[1]))handlerNames.add(match[1]);
  }
}
for(const name of handlerNames){
  const exposed=new RegExp(`(?:window\\.${name}\\s*=|Object\\.assign\\(window,\\{[\\s\\S]*?\\b${name}\\b[\\s\\S]*?\\}\\))`).test(taskPage);
  if(!exposed)failures.push(`Inline handler is not exposed to window: ${name}`);
}

// Validate named local imports against the actual exports of each module.
for(const match of taskPage.matchAll(/import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)){
  const specifier=match[2].split('?')[0];
  if(!specifier.startsWith('.'))continue;
  const importedPath=resolve(root,'assets/js',specifier);
  if(!existsSync(importedPath)){
    failures.push(`Missing imported module: ${specifier}`);
    continue;
  }
  const importedSource=readFileSync(importedPath,'utf8');
  for(const part of match[1].split(',').map(value=>value.trim()).filter(Boolean)){
    const originalName=part.split(/\s+as\s+/)[0].trim();
    const exported=new RegExp(`export\\s+(?:async\\s+)?(?:function|class|const|let|var)\\s+${originalName}\\b`).test(importedSource)
      ||new RegExp(`export\\s*\\{[^}]*\\b${originalName}\\b[^}]*\\}`).test(importedSource);
    if(!exported)failures.push(`Missing export ${originalName} from ${specifier}`);
  }
}

const requiredContracts=[
  ['Quick-add action','onclick="commitQuickAdd()"'],
  ['PDF attachment support','accept=".pdf,'],
  ['Attachment upload','uploadTaskAttachment(event)'],
  ['Attachment delete','deleteTaskAttachment'],
  ['Start transition','startSelectedTask'],
  ['Complete transition','completeSelectedTask'],
  ['Approval transition','approveSelectedTask'],
  ['Return transition','returnTaskForCorrection'],
  ['Completed-task reopen','adminReopenCompletedTask']
];
for(const [label,contract] of requiredContracts){
  if(!taskHtml.includes(contract)&&!taskPage.includes(contract))failures.push(`Missing workflow contract: ${label}`);
}

assert.equal(failures.length,0,failures.join('\n'));
console.log(`Phase-three quality gate passed: ${handlerNames.size} UI handlers and ${requiredContracts.length} workflow contracts.`);
