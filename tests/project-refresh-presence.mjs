import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const source=readFileSync('assets/js/projects-page.js','utf8');
let loads=0,queries=0;
const builder=name=>({name,select(){return this},eq(){return this},is(){return this}});
const ctx={project:{id:'p',revision:1},tasks:[{id:'t',revision:1}],files:[],busy:false,viewPending:false,draftDirty:false,detailOpen:false,tab:'gantt',document:{hidden:false,activeElement:null},sb:{from:builder},notice:{},query:async b=>{queries++;return b.name==='projects'?[{id:'p',revision:2}]:b.name==='tasks'?[{id:'t',revision:1}]:[]},loadProject:async()=>loads++};
vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function viewSignature('),source.indexOf("addEventListener('pagehide'")),ctx);
ctx.draftDirty=true;await ctx.refreshProjectView();assert.equal(queries,0,'Background refresh must preserve dirty input');
ctx.draftDirty=false;ctx.detailOpen=true;await ctx.refreshProjectView();assert.equal(queries,0,'Task detail must retain its editor');
ctx.detailOpen=false;await ctx.refreshProjectView();assert.equal(loads,1,'Changed revisions refresh read-only project views');
ctx.query=async b=>{ctx.draftDirty=true;return b.name==='projects'?[{revision:3}]:[]};await ctx.refreshProjectView();assert.equal(loads,1,'A draft started during a fetch must not be replaced');assert.equal(ctx.viewPending,false);
// Presence failures display unknown rather than inventing online/offline states.
let ui='';Object.assign(ctx,{presencePending:false,presence:[{user_id:'u',online:true}],tab:'chat',detailOpen:false,host:{querySelector:()=>({set innerHTML(x){ui=x}})},teamPresence:()=>ctx.presence.length?'known':'unknown',rpc:async()=>{throw Error('offline')}});
vm.runInContext(source.slice(source.indexOf('async function refreshPresence('),source.indexOf('function chat(panel)')),ctx);await ctx.refreshPresence();assert.equal(ui,'unknown');assert.equal(ctx.presencePending,false);
console.log('Project refresh protects drafts and detail views; failed presence remains unknown.');
