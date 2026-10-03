import {randomUUID} from 'node:crypto';
import {Buffer} from 'node:buffer';
export const uid=()=>randomUUID();
export function seed(){
 const users=[{id:'admin',name:'مسؤول النظام',role:'admin',department:'إدارة النظام'},{id:'manager',name:'سالم — مدير المبيعات',role:'manager',department:'المبيعات'},{id:'omar',name:'عمر — المبيعات',role:'employee',manager:'manager',department:'المبيعات'},{id:'nora',name:'نورة — العمليات',role:'employee',manager:'operations',department:'العمليات'},{id:'operations',name:'مازن — مدير العمليات',role:'manager',department:'العمليات'}];
 const conversations=[{id:'sales',title:'فريق المبيعات',type:'group',owner:'manager',members:['manager','omar']},{id:'project',title:'مشروع تحسين تسليم الطلبات',type:'project',owner:'operations',members:['manager','omar','nora','operations']},{id:'announcements',title:'إعلانات الشركة',type:'announcement',owner:'admin',members:users.map(x=>x.id)},{id:'direct',title:'',type:'direct',owner:'manager',members:['manager','omar']}];
 const now=Date.now();const messages=[{id:'welcome',conversation:'announcements',sender:'admin',body:'أهلًا بفريق العمل. هذه نسخة تجريبية للتواصل؛ جميع الأسماء والبيانات هنا وهمية.',seq:1,created:new Date(now-3600000).toISOString(),mentions:[],reactions:[]},{id:'sales-msg',conversation:'sales',sender:'manager',body:'صباح الخير يا فريق المبيعات. نحتاج مراجعة التقرير الأسبوعي قبل الخميس.',seq:2,created:new Date(now-1800000).toISOString(),mentions:['omar'],reactions:[]},{id:'project-msg',conversation:'project',sender:'operations',body:'نناقش هنا تحسين تسليم الطلبات بين المبيعات والعمليات. ملفات المشروع والنقاشات في مكان واحد.',seq:3,created:new Date(now-900000).toISOString(),mentions:[],reactions:[]},{id:'direct-msg',conversation:'direct',sender:'omar',body:'أرسلت التقرير الأولي. هل نراجع الملاحظات هنا؟',seq:4,created:new Date(now-600000).toISOString(),mentions:[],reactions:[]}];
 return {users,conversations,messages,tasks:[],reads:{},saved:{},favorites:{},muted:{},presence:{},devices:{},availability:{},preferences:{},notifications:[],following:{},threadReads:{},seq:4};
}
export class Fault extends Error{constructor(status,message){super(message);this.status=status;}}
const fail=(s,m)=>{throw new Fault(s,m);};
export function user(state,id){return state.users.find(x=>x.id===id)||fail(401,'الحساب التجريبي غير متاح.');}
export function conversation(state,id,who){const c=state.conversations.find(x=>x.id===id);if(!c||!(c.members.includes(who)||(c.type==='task'&&state.tasks.some(t=>t.conversation===c.id&&canTask(state,t,who)))))fail(403,'لا تملك صلاحية هذه المحادثة.');return c;}
export function canTask(state,t,who){const p=user(state,who);return p.role==='admin'||t.creator===who||t.assignee===who||user(state,t.assignee).manager===who;}
export function migrate(state){
 for(const key of ['devices','availability','preferences','following','threadReads'])state[key]??={};state.notifications??=[];return state;
}
export function presenceStatus(state,id,now=Date.now()){
 migrate(state);const devices=Object.values(state.devices).filter(d=>d.user===id&&now-d.seen<65000);
 // Legacy heartbeat data is used only for persisted v1 trials.
 if(!devices.length&&now-(state.presence[id]||0)>=65000)return 'offline';
 if(state.availability[id]==='dnd')return 'dnd';
 if(devices.length)return devices.some(d=>now-d.active<180000)?'available':'away';
 return 'available';
}
export function notificationSettings(state,who){return {sound:false,preview:true,desktop:false,quiet:false,start:22,end:7,groups:'mentions',...(state.preferences?.[who]||{})};}
export function notificationAllowed(state,who,n,now=Date.now()){
 const prefs=notificationSettings(state,who);const h=Number(new Intl.DateTimeFormat('en-US',{hour:'numeric',hourCycle:'h23',timeZone:'Asia/Riyadh'}).format(now));
 const quiet=prefs.quiet&&(prefs.start<prefs.end?h>=prefs.start&&h<prefs.end:h>=prefs.start||h<prefs.end);
 return !quiet&&presenceStatus(state,who,now)!=='dnd'&&!state.muted[who]?.includes(n.conversation);
}
function notifyMessage(state,c,m){
 const root=m.thread&&state.messages.find(x=>x.id===m.thread);
 for(const who of c.members.filter(x=>x!==m.sender)){
  const kind=c.type==='direct'?'direct':m.mentions.includes(who)?'mention':root&&(root.sender===who||state.following[who]?.includes(root.id))?'thread':c.type==='announcement'?'announcement':notificationSettings(state,who).groups==='all'?'group':null;
  if(kind)state.notifications.push({id:uid(),user:who,conversation:c.id,message:m.id,kind,created:m.created,read:false,delivered:false});
 }
}
export function snapshot(state,who,{includeFileBytes=false}={}){
 migrate(state);const p=user(state,who),conversations=state.conversations.filter(c=>c.members.includes(who)||(c.type==='task'&&state.tasks.some(t=>t.conversation===c.id&&canTask(state,t,who))));const ids=new Set(conversations.map(c=>c.id));
 return {me:p,users:state.users.map(u=>({...u,status:presenceStatus(state,u.id),online:presenceStatus(state,u.id)!=='offline'})),conversations,messages:state.messages.filter(m=>ids.has(m.conversation)).map(m=>({...m,file:m.file?(includeFileBytes?m.file:{id:m.file.id,name:m.file.name,type:m.file.type,size:m.file.size}):null,task:m.task?(canTask(state,state.tasks.find(t=>t.id===m.task),who)?state.tasks.find(t=>t.id===m.task):{id:m.task,restricted:true}):null})),tasks:state.tasks.filter(t=>canTask(state,t,who)),reads:state.reads[who]||{},saved:state.saved[who]||[],favorites:state.favorites[who]||[],muted:state.muted[who]||[],following:state.following[who]||[],threadReads:state.threadReads[who]||{},preferences:notificationSettings(state,who),notifications:state.notifications.filter(n=>n.user===who&&ids.has(n.conversation)),seq:state.seq};
}
export function command(state,who,action,data={}){
 migrate(state);const p=user(state,who);
 if(action==='presence'){
  if(data.device){if(!/^[a-zA-Z0-9-]{8,100}$/.test(data.device))fail(400,'الجلسة غير صحيحة.');
   const now=Date.now();state.devices[who+':'+data.device]={user:who,seen:now,active:Math.min(now,Number(data.active)||now),viewing:data.viewing&&state.conversations.some(c=>c.id===data.viewing&&c.members.includes(who))?data.viewing:null,thread:data.thread||null};
   for(const [key,d] of Object.entries(state.devices))if(now-d.seen>86400000)delete state.devices[key];
  }else state.presence[who]=Date.now();return {ok:true};
 }
 if(action==='availability'){if(!['auto','dnd'].includes(data.status))fail(400,'حالة غير صحيحة.');state.availability[who]=data.status;return {ok:true};}
 if(action==='preferences'){
  const prefs=notificationSettings(state,who);for(const key of ['sound','preview','desktop','quiet'])if(key in data){if(typeof data[key]!=='boolean')fail(400,'إعداد غير صحيح.');prefs[key]=data[key];}
  for(const key of ['start','end'])if(key in data){if(!Number.isInteger(data[key])||data[key]<0||data[key]>23)fail(400,'ساعة غير صحيحة.');prefs[key]=data[key];}
  if(data.groups){if(!['all','mentions'].includes(data.groups))fail(400,'إعداد غير صحيح.');prefs.groups=data.groups;}state.preferences[who]=prefs;return prefs;
 }
 if(action==='notificationRead'){
  for(const n of state.notifications)if(n.user===who&&(data.all||n.id===data.id))n.read=true;return {ok:true};
 }
 if(action==='notificationClaim'){
  const n=state.notifications.find(n=>n.id===data.id&&n.user===who);if(!n)fail(403,'الإشعار غير متاح.');
  conversation(state,n.conversation,who);if(n.delivered||n.read)return {show:false};n.delivered=true;
  const message=state.messages.find(m=>m.id===n.message);const viewing=Object.values(state.devices).some(d=>d.user===who&&Date.now()-d.seen<65000&&d.viewing===n.conversation&&(message?.thread?d.thread===message.thread:!d.thread));
  return {show:!viewing&&notificationAllowed(state,who,n)};
 }
 if(action==='createConversation'){
  if(!['direct','group'].includes(data.type))fail(400,'نوع المحادثة غير صحيح.');
  const members=[...new Set([who,...(data.members||[])])];if(members.length<2||members.length>30)fail(400,'اختر عضوًا واحدًا على الأقل.');members.forEach(x=>user(state,x));
  if(data.type==='direct'&&members.length!==2)fail(400,'المحادثة المباشرة بين شخصين.');
  if(data.type==='direct'){const found=state.conversations.find(c=>c.type==='direct'&&c.members.length===2&&members.every(x=>c.members.includes(x)));if(found)return found;}
  const title=String(data.title||'').trim();if(data.type==='group'&&(!title||title.length>80))fail(400,'اكتب اسم المجموعة (حتى ٨٠ حرفًا).');
  const c={id:uid(),type:data.type,title,owner:who,members};state.conversations.push(c);return c;
 }
 const c=conversation(state,data.conversation,who);
 if(action==='updateMembers'){
  if(c.type!=='group'||!(c.owner===who||p.role==='admin'))fail(403,'تعديل الأعضاء متاح لمسؤول المجموعة.');
  const members=[...new Set([c.owner,...(data.members||[])])];if(members.length<2||members.length>30)fail(400,'المجموعة تحتاج عضوين على الأقل.');members.forEach(id=>user(state,id));c.members=members;return c;
 }
 if(action==='read'){
  if(data.thread&&!state.messages.some(m=>m.id===data.thread&&m.conversation===c.id&&!m.thread))fail(403,'النقاش غير متاح.');
  const rows=state.messages.filter(m=>m.conversation===c.id&&(data.thread?m.thread===data.thread:!m.thread));const last=Math.max(0,...rows.map(m=>m.seq));
  const map=data.thread?(state.threadReads[who]??={}):(state.reads[who]??={}),key=data.thread||c.id;map[key]=Math.max(map[key]||0,Math.min(Number(data.seq)||0,last));
  const readIds=new Set(rows.filter(m=>m.seq<=map[key]).map(m=>m.id));for(const n of state.notifications)if(n.user===who&&readIds.has(n.message))n.read=true;return {ok:true};
 }
 if(action==='follow'){
  const root=state.messages.find(m=>m.id===data.message&&m.conversation===c.id&&!m.thread);if(!root)fail(403,'النقاش غير متاح.');
  const set=new Set(state.following[who]||[]);set.has(root.id)?set.delete(root.id):set.add(root.id);state.following[who]=[...set];return {ok:true};
 }
 if(action==='favorite'||action==='mute'){const key=action==='favorite'?'favorites':'muted';state[key][who]??=[];const set=new Set(state[key][who]);set.has(c.id)?set.delete(c.id):set.add(c.id);state[key][who]=[...set];return {ok:true};}
 if(action==='message'){
  if(c.type==='announcement'&&p.role!=='admin')fail(403,'نشر الإعلانات متاح لمسؤول النظام في التجربة.');
  const duplicate=state.messages.find(m=>m.sender===who&&m.clientId===data.clientId);if(duplicate){if(duplicate.conversation!==c.id||duplicate.body!==String(data.body||'').trim()||(duplicate.reply||null)!==(data.reply||null))fail(409,'معرّف الرسالة مستخدم لرسالة أخرى.');return duplicate;}
  if(!/^[a-zA-Z0-9-]{8,100}$/.test(data.clientId||''))fail(400,'معرّف الرسالة مطلوب.');
  const body=String(data.body||'').trim();if(body.length>5000||(!body&&!data.file))fail(400,'اكتب رسالة حتى ٥٠٠٠ حرف أو أرفق ملفًا.');
  if(data.reply&&!state.messages.some(m=>m.id===data.reply&&m.conversation===c.id))fail(400,'الرسالة المردود عليها ليست في المحادثة.');
  const mentions=[...new Set(data.mentions||[])];if(mentions.some(id=>!c.members.includes(id)))fail(400,'الإشارة متاحة لأعضاء المحادثة فقط.');
  let file=null;
  if(data.file){const f={...data.file};const fallback={docx:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',pdf:'application/pdf',txt:'text/plain',png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',webp:'image/webp'};if(['','application/octet-stream','application/zip','application/x-zip-compressed'].includes(f.type||''))f.type=fallback[String(f.name||'').split('.').pop().toLowerCase()]||f.type;const allowed=['image/png','image/jpeg','image/webp','application/pdf','text/plain','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
   if(!allowed.includes(f.type)||typeof f.base64!=='string'||!/^[A-Za-z0-9+/]*={0,2}$/.test(f.base64)||Buffer.byteLength(f.base64,'base64')>10*1024*1024)fail(400,'الملف غير مدعوم أو يتجاوز ١٠ ميجابايت.');
   file={id:uid(),name:String(f.name).replace(/[\r\n"/\\]/g,'_').slice(0,120)||'ملف',type:f.type,base64:f.base64,size:Buffer.byteLength(f.base64,'base64')};
  }
  const original=data.reply&&state.messages.find(m=>m.id===data.reply);const thread=original?(original.thread||original.id):null;
  const m={id:uid(),thread,clientId:data.clientId,conversation:c.id,sender:who,body,mentions,reply:data.reply||null,file,reactions:[],created:new Date().toISOString(),seq:++state.seq};state.messages.push(m);if(thread){state.following[who]??=[];if(!state.following[who].includes(thread))state.following[who].push(thread);}notifyMessage(state,c,m);return m;
 }
 const m=state.messages.find(x=>x.id===data.message&&x.conversation===c.id);if(!m)fail(404,'الرسالة غير موجودة.');
 if(action==='save'){state.saved[who]??=[];const set=new Set(state.saved[who]);set.has(m.id)?set.delete(m.id):set.add(m.id);state.saved[who]=[...set];return {ok:true};}
 if(action==='react'){const set=new Set(m.reactions);set.has(who)?set.delete(who):set.add(who);m.reactions=[...set];return {ok:true};}
 if(action==='pin'){if(c.type!=='direct'&&c.owner!==who&&p.role!=='admin')fail(403,'التثبيت متاح لمسؤول المجموعة.');m.pinned=!m.pinned;return {ok:true};}
 if(action==='createTask'){
  if(m.task)fail(409,'الرسالة مرتبطة بمهمة بالفعل.');
  const target=user(state,data.assignee);if(!(p.role==='admin'||data.assignee===who||p.role==='manager'&&target.manager===who))fail(403,'المسند إليه خارج صلاحيات إسناد المهام.');
  const title=String(data.title||'').trim();if(!title||title.length>180||!/^\d{4}-\d{2}-\d{2}$/.test(data.due||'')||!Number.isFinite(Date.parse(data.due+'T00:00Z'))||new Date(data.due+'T00:00Z').toISOString().slice(0,10)!==data.due)fail(400,'العنوان وتاريخ الاستحقاق الصحيح مطلوبان.');
  const members=[...new Set([who,target.id,target.manager].filter(Boolean))];const thread={id:uid(),type:'task',title,owner:who,members};state.conversations.push(thread);
  const t={id:uid(),title,assignee:target.id,creator:who,due:data.due,status:'لم تبدأ',conversation:thread.id,source:m.id,sourceConversation:c.id};state.tasks.push(t);m.task=t.id;return t;
 }
 if(action==='linkTask'){const t=state.tasks.find(x=>x.id===data.task);if(!t||!canTask(state,t,who))fail(403,'لا تملك صلاحية المهمة.');if(m.task)fail(409,'الرسالة مرتبطة بمهمة بالفعل.');m.task=t.id;return t;}
 fail(400,'الإجراء غير مدعوم.');
}
