import {pathToFileURL} from 'node:url';
import {SUITES} from './plan.mjs';
export function verifyGate(needs){
  if(needs?.plan?.result!=='success')throw Error('Change classification did not succeed');
  if(needs?.audit?.result!=='success')throw Error('Mandatory regression audit did not succeed');
  const selected=JSON.parse(needs.plan.outputs.suites);
  if(!Array.isArray(selected)||selected.some(s=>!SUITES.includes(s))||new Set(selected).size!==selected.length)throw Error('Invalid suite plan');
  if(!['full','module','design','docs'].includes(needs.plan.outputs.kind))throw Error('Invalid verification type');
  if(needs.plan.outputs.kind==='full'&&selected.length!==SUITES.length)throw Error('Full verification must include every suite');
  if((selected.length===0)!==(needs.plan.outputs.kind==='docs'))throw Error('Only documentation may omit module suites');
  const expected=selected.length?'success':'skipped';
  if(needs?.checks?.result!==expected)throw Error(`Module checks must be ${expected}; received ${needs?.checks?.result}`);
  return true;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  verifyGate(JSON.parse(process.env.CI_NEEDS));
  console.log('PASS: classification, mandatory audit and every selected suite succeeded');
}
