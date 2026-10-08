import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';
import {freshJob,jobValidation} from '../assets/js/job-workflow-model.mjs';
const nodes=new Map();function node(id){if(!nodes.has(id))nodes.set(id,{innerHTML:'',value:'',hidden:false,disabled:false,classList:{toggle(){}},addEventListener(){}});return nodes.get(id);}
let source=readFileSync(new URL('../assets/js/job-authoring-page.js',import.meta.url),'utf8');source=source.slice(source.indexOf('const sb='),source.indexOf('boot().catch('));
const ctx=vm.createContext({window:{atwarGetSupabase:async()=>({}),addEventListener(){}},document:{getElementById:node,querySelectorAll:()=>[]},freshJob,jobValidation,structuredClone,crypto:{randomUUID:()=> 'test'},URLSearchParams,console});
await vm.runInContext('(async()=>{'+source+';profile={role:"admin"};users=[];jobs=[];draft.content.kpis=[{name:"مؤشر",weight:100}];for(step=0;step<5;step++){render();globalThis.outputs[step]=document.getElementById("authoringBody").innerHTML;} })()',Object.assign(ctx,{outputs:[]}));
assert.match(ctx.outputs[0],/المدير المباشر/);assert.match(ctx.outputs[0],/سبب تعيين البديل/);assert.match(ctx.outputs[1],/إضافة بند/);assert.match(ctx.outputs[2],/مصدر القياس/);assert.match(ctx.outputs[2],/الوزن %/);assert.match(ctx.outputs[3],/العلاقات الخارجية/);assert.match(ctx.outputs[4],/متطلبات الإرسال المتبقية/);
console.log('Actual authoring renderer: five steps and action labels passed');
