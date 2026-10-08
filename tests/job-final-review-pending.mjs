import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
for (const [file,entity,tab] of [['job-review-page.js','job','review'],['job-library-page.js','current','proposals']]) {
 const source=readFileSync(new URL('../assets/js/'+file,import.meta.url),'utf8');
 const start=source.indexOf('async function finishFinalReview()');
 const body=source.slice(start,source.indexOf('\n}',start)+2);
 async function run(rows,error=null,readError=null) {
  let calls=0,rendered=0,messages=[];
  const chain={select(){return this},eq(){return this},order:async()=>({data:rows,error:readError})};
  const context={sb:{from:()=>chain,rpc:async()=>{calls++;return {error,data:{id:'job',final_reviewed_at:'done'}}}},[entity]:{id:'job'},proposals:[],editing:true,activeTab:'overview',toast:m=>messages.push(m),render:()=>rendered++,renderEditor:()=>rendered++,loadRelated:async()=>{},loadReviewData:async()=>{}};
  vm.createContext(context);await vm.runInContext(body+';finishFinalReview()',context);
  return {calls,rendered,messages,context};
 }
 const blocked=await run([{status:'PENDING',action:'DELETE'},{status:'PENDING',action:'MODIFY'}]);
 assert.equal(blocked.calls,0);assert.equal(blocked.context.activeTab,tab);assert.equal(blocked.context.editing,false);assert.match(blocked.messages[0],/2/);assert.equal(blocked.rendered,1);
 const allowed=await run([{status:'PENDING',action:'COMMENT'},{status:'ACCEPTED',action:'MODIFY'}]);assert.equal(allowed.calls,1);assert.equal(allowed.context[entity].final_reviewed_at,'done');
 const failedRead=await run([],null,{message:'offline'});assert.equal(failedRead.calls,0);assert.match(failedRead.messages[0],/تعذر التحقق/);
 const raced=await run([],{message:'Resolve pending proposals first'});assert.equal(raced.context.activeTab,tab);assert.match(raced.messages[0],/أضيفت مقترحات/);
}
console.log('Final review pending proposals and concurrent changes passed');
