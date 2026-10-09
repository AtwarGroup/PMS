import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync(new URL('../communication/app.mjs',import.meta.url),'utf8');
const handler=source.slice(source.indexOf("$('fileInput').onchange="),source.indexOf("$('mention').onclick="));
const selection=source.slice(source.indexOf('function selectConversation('),source.indexOf('async function sync('));
function harness(){
 const readers=[],notices=[];
 const nodes=Object.fromEntries(['fileInput','attachmentBar','send','messageInput','layout'].map(id=>[id,{files:[],value:'',hidden:true,disabled:true,focus(){},classList:{toggle(){}}}]));
 const ctx=vm.createContext({nodes,readers,notices,innerWidth:1000,
 FileReader:class{readAsDataURL(f){readers.push({finish:()=>{this.result='data:text/plain;base64,dGVzdA==';this.onload();},fail:()=>this.onerror(new Error('read failed'))});}}});
 vm.runInContext(`let active='A',epoch=0,attachmentReadGeneration=0,file=null,state={me:{id:'test'}},threadRoot=null,currentPage='communication',reply=null,mentions=[],detailTask=null,notificationTarget=null,conversationView='chat';
 const $=id=>nodes[id],esc=x=>x,attachmentType=f=>f.type,notice=x=>notices.push(x),store=()=>{},load=()=>'',draftKey=()=>'',closeThread=()=>{},navigatePage=()=>{},renderList=()=>{},renderHead=()=>{},renderMessages=()=>{},renderDetails=()=>{},heartbeat=()=>{};`+selection+handler,ctx);
 return {ctx,nodes,readers,notices,choose(name='test.txt',size=10){nodes.fileInput.files=[{name,size,type:'text/plain'}];nodes.fileInput.value=name;return vm.runInContext("$('fileInput').onchange()",ctx);},switch(id){vm.runInContext('selectConversation('+JSON.stringify(id)+')',ctx);},file(){return vm.runInContext('file',ctx);}};
}
{
 const h=harness(),p=h.choose();h.readers[0].finish();await p;assert.equal(h.file().name,'test.txt');assert.equal(h.nodes.attachmentBar.hidden,false);assert.equal(h.nodes.send.disabled,false);
}
{
 const h=harness(),p=h.choose();h.switch('B');h.readers[0].finish();await p;assert.equal(h.file(),null);assert.equal(h.nodes.attachmentBar.hidden,true);
}
{
 const h=harness(),p=h.choose();h.switch('B');h.switch('A');h.readers[0].finish();await p;assert.equal(h.file(),null);
}
{
 const h=harness(),first=h.choose('old.txt'),second=h.choose('new.txt');h.readers[1].finish();await second;h.readers[0].finish();await first;assert.equal(h.file().name,'new.txt');
}
{
 const h=harness(),p=h.choose();vm.runInContext('epoch++',h.ctx);h.readers[0].finish();await p;assert.equal(h.file(),null);
}
{
 const h=harness(),p=h.choose();h.readers[0].fail();await p;assert.equal(h.file(),null);assert.equal(h.notices.at(-1),'read failed');assert.equal(h.nodes.fileInput.value,'');
}
{
 const h=harness();await h.choose('large.txt',10*1024*1024+1);assert.equal(h.file(),null);assert.equal(h.readers.length,0);assert.match(h.notices.at(-1),/١٠/);
}
console.log('PASS attachment context: valid selection, switch, A-B-A, overlapping reads, identity epoch, read failure, size limit');
