import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
// A small DOM model exercises the public dialog API and actual keyboard events.
const timers=new Map();let timerId=0;
class Node{
 constructor(tag,document){this.tagName=tag.toUpperCase();this.document=document;this.children=[];this.attrs={};this.style={};this.events={};this.tabIndex=['BUTTON','INPUT','TEXTAREA','SELECT','A'].includes(this.tagName)?0:-1;this.disabled=false;this.hidden=false;this.value='';}
 get isConnected(){return this===this.document.body||Boolean(this.parent?.isConnected);}
 append(...nodes){for(const node of nodes){node.parent=this;this.children.push(node);}}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(n=>n!==this);this.parent=null;}
 setAttribute(k,v){this.attrs[k]=String(v);}removeAttribute(k){delete this.attrs[k];}
 contains(node){return node===this||this.children.some(n=>n.contains(node));}
 querySelectorAll(selector){const all=this.children.flatMap(n=>[n,...n.querySelectorAll('*')]);if(selector==='*')return all;if(['h2','button','input'].includes(selector))return all.filter(n=>n.tagName===selector.toUpperCase());return all.filter(n=>['BUTTON','INPUT','TEXTAREA','SELECT','A'].includes(n.tagName)||n.attrs.tabindex!==undefined);}
 querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
 addEventListener(k,fn){this.events[k]=fn;}removeEventListener(k,fn){if(this.events[k]===fn)delete this.events[k];}
 getClientRects(){return this.isConnected&&!this.hidden?[{}]:[];}
 focus(){this.document.activeElement=this;}select(){}click(){this.onclick?.({target:this});}
 key(key,shiftKey=false){const event={key,shiftKey,prevented:false,stopped:false,preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;}};this.onkeydown?.(event);for(let node=this;node&&!event.stopped;node=node.parent)node.events.keydown?.(event);return event;}
}
const document={activeElement:null,createElement(tag){return new Node(tag,this)},querySelector(){return null}};document.body=new Node('body',document);document.body.style.overflow='auto';
const window={};vm.runInNewContext(readFileSync(new URL('../assets/js/ui-feedback.js',import.meta.url),'utf8'),{window,document,setTimeout(fn){timers.set(++timerId,fn);return timerId;},clearTimeout(id){timers.delete(id);}});
const flush=()=>{for(const [id,fn] of [...timers]){timers.delete(id);fn();}};
const trigger=document.createElement('button');document.body.append(trigger);trigger.focus();
let result=window.AtwarUI.confirm({title:'Confirm',message:'Review this action'});flush();
let dialog=document.body.children.at(-1).children[0];let buttons=dialog.querySelectorAll('button');
assert.equal(document.activeElement,buttons[0]);assert.equal(document.body.style.overflow,'hidden');
assert.equal(dialog.attrs['aria-labelledby'],dialog.querySelector('h2').id);assert.ok(dialog.attrs['aria-describedby']);
assert.equal(buttons[0].key('Tab',true).prevented,true);assert.equal(document.activeElement,buttons[1]);
assert.equal(buttons[1].key('Tab').prevented,true);assert.equal(document.activeElement,buttons[0]);
buttons[0].key('Escape');assert.equal(await result,false);assert.equal(document.activeElement,trigger);assert.equal(document.body.style.overflow,'auto');assert.equal(timers.size,0);
result=window.AtwarUI.confirm({danger:true});flush();dialog=document.body.children.at(-1).children[0];buttons=dialog.querySelectorAll('button');assert.equal(document.activeElement,buttons[1],'Destructive confirmation starts at cancel');buttons[0].click();assert.equal(await result,true);
result=window.AtwarUI.prompt({required:true,multiline:false,title:'Decision'});flush();dialog=document.body.children.at(-1).children[0];const input=dialog.querySelectorAll('input')[0];buttons=dialog.querySelectorAll('button');assert.equal(document.activeElement,input);
buttons[0].click();assert.equal(input.attrs['aria-invalid'],'true');assert.equal(dialog.isConnected,true);input.value='  Reviewed  ';input.oninput();assert.equal(input.attrs['aria-invalid'],undefined);input.key('Enter');assert.equal(await result,'Reviewed');assert.equal(document.activeElement,trigger);
// Nested dialogs restore scroll only after the last dialog closes.
const outer=window.AtwarUI.confirm({title:'Outer'});const outerDialog=document.body.children.at(-1).children[0];const inner=window.AtwarUI.confirm({title:'Inner'});flush();document.body.children.at(-1).children[0].querySelectorAll('button')[1].click();assert.equal(await inner,false);assert.equal(document.body.style.overflow,'hidden');outerDialog.querySelectorAll('button')[1].click();assert.equal(await outer,false);assert.equal(document.body.style.overflow,'auto');
console.log('Dialog accessibility passed: names, focus loop/restore, Escape, safe initial focus, required-field validation, Enter, nested scroll lock.');

const taskSource=readFileSync(new URL('../assets/js/tasks-page.js',import.meta.url),'utf8');
const delegationSource=taskSource.slice(taskSource.indexOf('function appConfirm('),taskSource.indexOf('function updateRangeVisual('));
const requests=[],taskContext={window:{AtwarUI:{confirm:args=>{requests.push(args);return Promise.resolve(true)},prompt:args=>{requests.push(args);return Promise.resolve('Note')}}}};
vm.createContext(taskContext);vm.runInContext(delegationSource,taskContext);
assert.equal(await taskContext.appConfirm('Review action','Confirm task'),true);assert.equal(await taskContext.appPrompt('Give reason','Task note','Write here'),'Note');
assert.equal(requests[0].title,'Confirm task');assert.equal(requests[1].placeholder,'Write here');assert.equal(requests[1].multiline,true);
console.log('Task dialogs delegate to the shared accessible components.');
