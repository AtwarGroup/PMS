import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {historyQuery,historyPage,mergeHistory} from '../assets/js/project-history.mjs';
const source=readFileSync('assets/js/projects-page.js','utf8');
const row=n=>({id:`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`,created_at:'2026-10-09T12:00:00.123456+00:00'});
let pending=[],reads=0,html='';
const feed={scrollTop:50,scrollHeight:100,clientHeight:30,set innerHTML(v){html=v;this.scrollHeight+=200;},get innerHTML(){return html;}};
const button={disabled:false,hidden:false,isConnected:true};const status={},unread={hidden:true},draft={value:'مسودة محفوظة'};
const builder={select(){return this},eq(){return this},or(){return this},order(){return this},limit(){return this}};
const ctx={historyQuery,historyPage,mergeHistory,project:{id:'p'},tab:'chat',detailOpen:false,chatEpoch:1,messageCursor:row(150),olderMessages:true,messageHistoryRequest:null,eventHistoryRequest:null,chatRefreshRequest:null,messages:[row(150)],document:{hidden:false},sb:{from:()=>builder},host:{querySelector:s=>({'#chatFeed':feed,'#chatOlder':button,'#chatSyncStatus':status,'#chatUnread':unread,'#projectPanel':{}}[s])},query(){reads++;return new Promise(resolve=>pending.push(resolve));},chatFeed:()=>JSON.stringify(ctx.messages),wireChat(){},Set,Promise,console};
vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function chatStatus('),source.indexOf('function settings(panel)')),ctx);
const request=ctx.loadOlderMessages();assert.equal(button.disabled,true);await ctx.loadOlderMessages();assert.equal(reads,1,'Duplicate older-page clicks are coalesced');pending.shift()([row(149),row(148)]);await request;
assert.equal(feed.scrollTop,250,'Prepending older messages preserves the original reading anchor');assert.equal(draft.value,'مسودة محفوظة');assert.equal(button.hidden,true);assert.equal(button.disabled,false);assert.equal(ctx.messages.length,3);
ctx.olderMessages=true;const stale=ctx.loadOlderMessages();ctx.chatEpoch++;ctx.project={id:'other'};ctx.messages=[];html='other';pending.shift()([row(147)]);await stale;assert.equal(html,'other','Stale older responses cannot replace a newly opened conversation');assert.equal(ctx.messages.length,0);
// Recover more than one page of messages sent while disconnected.
ctx.project={id:'p'};ctx.messages=[row(1)];ctx.messageCursor=row(1);ctx.chatRefreshRequest=null;const live=ctx.refreshChat();pending.shift()(Array.from({length:101},(_,i)=>row(205-i)));await new Promise(r=>setImmediate(r));assert.equal(pending.length,1);pending.shift()(Array.from({length:101},(_,i)=>row(105-i)));await new Promise(r=>setImmediate(r));pending.shift()([row(5),row(4),row(3),row(2),row(1)]);await live;assert.equal(ctx.messages.length,205,'Reconnect fills the gap before joining the cached history');assert.equal(new Set(ctx.messages.map(m=>m.id)).size,205);
console.log('History UI: coalesced paging, scroll/draft preservation, stale-response rejection and 204-message reconnect catch-up passed');
