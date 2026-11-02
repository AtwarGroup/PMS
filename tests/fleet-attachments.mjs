import assert from 'node:assert/strict';
import {quoteFileIds,validateFleetFiles,uploadFleetFiles,validateFleetUploadBudget} from '../assets/js/fleet-attachments.mjs';
assert.deepEqual(quoteFileIds({parts_file_id:'legacy'},'parts'),['legacy']);
assert.deepEqual(quoteFileIds({parts_file_ids:['a','b'],parts_file_id:'a'},'parts'),['a','b']);
assert.deepEqual(quoteFileIds({},'labor'),[]);
const files=['a','b'].map(name=>({name,type:'application/pdf',size:10}));let saved=[],fail=true;
const upload=async file=>{if(file.name==='b'&&fail){fail=false;throw Error('lost response');}return file.name;};
await assert.rejects(()=>uploadFleetFiles(files,upload,[],ids=>{saved=ids;}),/lost response/);
assert.deepEqual(saved,['a']);assert.deepEqual(await uploadFleetFiles(files,upload,saved),['a','b']);
for(const file of [{type:'text/html',size:10},{type:'image/png',size:5242881},{type:'image/png',size:0}])assert.throws(()=>validateFleetFiles([file]),/5 ميجابايت/);
let calls=0;await assert.rejects(()=>uploadFleetFiles([...files,{type:'text/html',size:10}],async()=>{calls++;}),/PDF/);assert.equal(calls,0);
assert.throws(()=>validateFleetFiles(Array.from({length:7},()=>({type:'image/png',size:5242880}))),/30 ميجابايت/);
console.log('PASS batch selection preflight, legacy IDs, partial-failure retry and duplicate-free accumulation.');

const realFile = new File(['sample'], 'sample.pdf', {type:'application/pdf'});
const fullStore = Array.from({length:6}, (_,i)=>({kind:'invoice',size_bytes:5242880,content_hash:String(i)}));
await assert.rejects(()=>validateFleetUploadBudget([{kind:'invoice',file:realFile}],fullStore),/30 ميجابايت/);
const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256',await realFile.arrayBuffer()))].map(b=>b.toString(16).padStart(2,'0')).join('');
await validateFleetUploadBudget([{kind:'invoice',file:realFile}],[{kind:'invoice',size_bytes:realFile.size,content_hash:hash}]);

await assert.rejects(()=>validateFleetUploadBudget([{kind:'repair_photo',file:realFile}]),/PNG أو JPEG/);
