import {spawnSync} from 'node:child_process';
import {readFileSync,appendFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

export const SUITES=Object.freeze(['fleet','it','recruitment','policies','communication','core']);
const modulePaths=[
  [/^fleet\//,'fleet'],[/^it-support\//,'it'],[/^recruitment\//,'recruitment'],
  [/^policies\//,'policies'],[/^communication\//,'communication'],
  [/^assets\/(?:css|js)\/fleet[\w.-]*$/,'fleet'],
  [/^assets\/(?:css|js)\/it-(?:support|purchase)[\w.-]*$/,'it'],
  [/^assets\/(?:css|js)\/(?:recruitment|recruitment-[\w.-]+)\.(?:css|js|mjs)$/,'recruitment'],
  [/^assets\/(?:css|js)\/polic[\w.-]*$/,'policies']
];
export function planChanges(paths,{forceFull=false}={}){
  const full=reason=>({kind:'full',suites:[...SUITES],reason});
  if(forceFull)return full('Scheduled/manual/full verification');
  if(!Array.isArray(paths)||!paths.length)return full('No reliable change list');
  const suites=new Set();let design=true;
  for(const file of paths){
    if(typeof file!=='string'||!file||file.startsWith('/')||file.split('/').includes('..'))return full('Invalid path');
    if(/^(?:docs\/.*|README(?:\.[^/]+)?|CHANGELOG(?:\.[^/]+)?|lab\/.*)\.(?:md|txt)$/i.test(file)||/^(?:README|CHANGELOG)\.md$/i.test(file))continue;
    // Unknown, shared, database, dependency, test and pipeline changes fail closed.
    // Module mappings are deliberately limited to files owned by that module.
    const match=modulePaths.find(([pattern])=>pattern.test(file));
    if(!match)return full('Shared or unclassified path: '+file);
    suites.add(match[1]);
    if(!/\.(?:css|html|svg|png|jpe?g|webp)$/i.test(file))design=false;
  }
  return {kind:suites.size?(design?'design':'module'):'docs',suites:SUITES.filter(s=>suites.has(s)),reason:'Affected modules selected from all changed paths'};
}

function git(args){const r=spawnSync('git',args,{encoding:'utf8'});if(r.status!==0)throw Error('Unable to resolve changed commits');return r.stdout;}
export function eventPlan(eventName,event){
  if(['schedule','workflow_dispatch','merge_group'].includes(eventName))return planChanges([],{forceFull:true});
  let base,head;
  if(eventName==='pull_request'){base=event.pull_request?.base?.sha;head=event.pull_request?.head?.sha;}
  else if(eventName==='push'){base=event.before;head=event.after;}
  else return planChanges([],{forceFull:true});
  if(![base,head].every(s=>typeof s==='string'&&/^[a-f0-9]{40,64}$/.test(s)&&!/^0+$/.test(s)))return planChanges([],{forceFull:true});
  try{
    if(eventName==='pull_request')base=git(['merge-base',base,head]).trim();
    // --no-renames makes both old and new paths visible, including module moves.
    const paths=git(['diff','--name-only','--no-renames','-z',base,head,'--']).split('\0').filter(Boolean);
    return planChanges(paths);
  }catch{return {...planChanges([],{forceFull:true}),reason:'Diff unavailable; full verification required'};}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const event=JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH,'utf8'));
  const plan=eventPlan(process.env.GITHUB_EVENT_NAME,event);
  appendFileSync(process.env.GITHUB_OUTPUT,`suites=${JSON.stringify(plan.suites)}\nkind=${plan.kind}\n`);
  if(process.env.GITHUB_STEP_SUMMARY)appendFileSync(process.env.GITHUB_STEP_SUMMARY,`## Verification plan\n\nType: **${plan.kind}**\n\nSuites: ${plan.suites.join(', ')||'documentation only; audit and asset checks still required'}\n\n${JSON.stringify(plan.reason)}\n`);
  console.log(JSON.stringify(plan));
}
