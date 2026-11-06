import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
export const SUITE_COMMANDS={
  fleet:[['python3','scripts/test-fleet-import.py'],['npm','run','test:fleet:db'],['npm','run','test:fleet:ui'],['node','scripts/test-fleet-alerts.mjs']],
  it:[['node','scripts/test-it-v2.mjs'],['node','scripts/test-it-followup.mjs'],['node','scripts/test-it-auto-close.mjs'],['node','scripts/test-it-auto-close-ui.mjs']],
  recruitment:[['npm','run','test:recruitment:db'],['npm','run','test:recruitment:release'],['node','tests/browser/theme-recruitment.cjs']],
  policies:[['node','tests/browser/policy-editor.cjs'],['node','tests/browser/compensation-reader.cjs'],['node','tests/browser/leave-reader.cjs']],
  communication:[['node','tests/browser/communication-layout.cjs']],
  core:[
    ['node','scripts/test-action-history.mjs'],['node','scripts/test-business-conflict.mjs'],['node','scripts/test-attachment-viewer-ui.mjs'],
    ['node','tests/browser/notification-bfcache.cjs'],['node','tests/browser/unified-notifications.cjs'],
    ...['daily-work','library','employee-change','project','job-document'].map(n=>['node',`scripts/${n}-preview.mjs`]),
    ...['employee-access','account-modules','home-resilience','data-state','shell-loading','legacy-redirects','theme-legibility','theme-contract','unified-page-tabs','theme-dynamic','theme-runtime'].map(n=>['node',`tests/browser/${n}.cjs`])
  ]
};
export async function runSuite(suite){
if(!Object.hasOwn(SUITE_COMMANDS,suite))throw Error('Unknown verification suite');
const children=[];
function stop(){for(const child of children)child.kill('SIGTERM');}
process.on('SIGTERM',()=>{stop();process.exit(1)});process.on('SIGINT',()=>{stop();process.exit(1)});
async function server(command,args,port,env={}){
  const child=spawn(command,args,{stdio:['ignore','ignore','inherit'],env:{...process.env,...env}});children.push(child);
  let error;child.on('error',e=>error=e);
  for(let n=0;n<120;n++){
    if(error||child.exitCode!==null)throw error||Error('Preview server exited');
    try{if((await fetch(`http://127.0.0.1:${port}`,{signal:AbortSignal.timeout(1000)})).ok)return;}catch{}
    await delay(500);
  }throw Error('Preview server did not become ready');
}
try{
  if(['policies','core'].includes(suite))await server('python3',['-m','http.server','8765','--bind','127.0.0.1'],8765);
  if(suite==='recruitment')await server('node',['scripts/recruitment-preview.mjs'],4174,{PORT:'4174'});
  for(const [command,...args]of SUITE_COMMANDS[suite]){
    console.log(`::group::${command} ${args.join(' ')}`);
    const r=spawnSync(command,args,{stdio:'inherit',env:process.env});
    console.log('::endgroup::');
    if(r.error||r.status!==0)throw r.error||Error(`Verification failed: ${args.join(' ')} (${r.status??r.signal})`);
  }
}finally{stop();}

}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await runSuite(process.argv[2]);
