export function escapeHTML(value=''){
  return String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
}

export function isActiveProfile(profile){
  return !!profile && profile.active!==false && profile.status!=='inactive';
}

export function localDateISO(d=new Date()){
  if(!(d instanceof Date)||Number.isNaN(d.getTime()))return '';
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

export function parseDateOnly(value){
  if(!value)return null;
  const date=new Date(value+(String(value).length===10?'T00:00:00':''));
  return Number.isNaN(date.getTime())?null:date;
}

function calendarDaySerial(value){
  const date=value instanceof Date?value:parseDateOnly(value);
  if(!date||Number.isNaN(date.getTime()))return null;
  return Math.floor(Date.UTC(date.getFullYear(),date.getMonth(),date.getDate())/86400000);
}

export function calcDuration(start,end){
  const first=calendarDaySerial(start),last=calendarDaySerial(end);
  if(first===null||last===null)return 0;
  const days=last-first;
  return days>=0?days+1:0;
}

function approvalPausedDays(activity){
  const rows=(Array.isArray(activity)?activity:Object.values(activity||{}))
    .filter(Boolean).sort((a,b)=>Number(a.createdAt||0)-Number(b.createdAt||0));
  let submittedDay=null,paused=0;
  for(const row of rows){
    const day=calendarDaySerial(new Date(Number(row.createdAt||0)));
    if(day===null)continue;
    if(row.type==='submitted')submittedDay=day;
    else if(row.type==='reopened'&&submittedDay!==null){
      paused+=Math.max(0,day-submittedDay);
      submittedDay=null;
    }
  }
  return paused;
}

export function calcDelay(end,actualEnd,status,submittedAt,activity,now=new Date()){
  const endDay=calendarDaySerial(end);
  if(endDay===null)return 0;
  if(status==='مكتملة'&&!actualEnd&&!submittedAt)return 0;

  let compare=null;
  if((status==='بانتظار الاعتماد'||status==='مكتملة')&&submittedAt){
    compare=new Date(Number(submittedAt));
  }else if(actualEnd){
    compare=parseDateOnly(actualEnd);
  }else{
    compare=now;
  }

  const compareDay=calendarDaySerial(compare);
  return compareDay===null?0:Math.max(0,compareDay-endDay-approvalPausedDays(activity));
}

export function normalizeProgress(value){
  return Math.max(0,Math.min(100,Number.parseInt(value||0,10)||0));
}

function isISODate(value){
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value||''))&&!!parseDateOnly(value);
}

export function validateTaskFieldValue(task,field,value){
  const normalized=typeof value==='string'?value.trim():value;
  if(field==='title'){
    if(!normalized)return {ok:false,message:'عنوان المهمة مطلوب.'};
    if(String(normalized).length>200)return {ok:false,message:'عنوان المهمة يجب ألا يتجاوز 200 حرف.'};
  }
  if(field==='start'||field==='end'){
    if(!isISODate(normalized))return {ok:false,message:'صيغة التاريخ غير صالحة.'};
    const start=field==='start'?normalized:task.start;
    const end=field==='end'?normalized:task.end;
    if(start&&end&&String(start)>String(end))return {ok:false,message:'تاريخ الانتهاء يجب ألا يسبق تاريخ البدء.'};
  }
  if(field==='priority'&&!['normal','important','urgent'].includes(String(normalized))){
    return {ok:false,message:'قيمة الأولوية غير صالحة.'};
  }
  const limits={desc:5000,notes:5000,managerNotes:2000};
  if(limits[field]&&String(normalized||'').length>limits[field]){
    return {ok:false,message:`النص يتجاوز الحد المسموح (${limits[field]} حرف).`};
  }
  return {ok:true,value:normalized};
}

export function formatDateAR(value){
  if(!value)return '—';
  const date=parseDateOnly(value);
  if(!date)return String(value);
  return `${String(date.getDate()).padStart(2,'0')}/${String(date.getMonth()+1).padStart(2,'0')}/${date.getFullYear()}`;
}

export function priorityLabel(value){
  return ({normal:'عادية',important:'مهمة',urgent:'عاجلة'})[value]||'عادية';
}

export function smartDate(value,now=new Date()){
  const date=parseDateOnly(value);
  if(!date)return '—';
  const today=new Date(now);today.setHours(0,0,0,0);date.setHours(0,0,0,0);
  const difference=Math.round((date-today)/86400000);
  if(difference===0)return 'اليوم';
  if(difference===1)return 'غدًا';
  if(difference===-1)return 'أمس';
  return formatDateAR(value);
}

export function isToday(value,now=new Date()){
  const date=parseDateOnly(value);
  if(!date)return false;
  return date.getFullYear()===now.getFullYear()&&date.getMonth()===now.getMonth()&&date.getDate()===now.getDate();
}

export function roleLabel(role){
  return ({admin:'مدير النظام',manager:'مدير',employee:'موظف'})[role]||'موظف';
}

export function sortTaskRows(rows,{sortFilterValue='DEFAULT',isManagerView=false}={}){
  const priorityWeight={urgent:0,important:1,normal:2};
  const allRows=[...(rows||[])];
  const approvalRows=isManagerView?allRows.filter(task=>String(task.status||'').trim()==='بانتظار الاعتماد'):[];
  const normalRows=isManagerView?allRows.filter(task=>String(task.status||'').trim()!=='بانتظار الاعتماد'):allRows;
  const sortGroup=group=>{
    const result=[...group];
    if(sortFilterValue==='NEWEST')return result.sort((a,b)=>Number(b.createdAt||0)-Number(a.createdAt||0));
    if(sortFilterValue==='OLDEST')return result.sort((a,b)=>Number(a.createdAt||0)-Number(b.createdAt||0));
    if(sortFilterValue==='PRIORITY')return result.sort((a,b)=>(priorityWeight[a.priority||'normal']??2)-(priorityWeight[b.priority||'normal']??2)||String(a.end||'9999').localeCompare(String(b.end||'9999')));
    if(sortFilterValue==='DUE')return result.sort((a,b)=>String(a.end||'9999').localeCompare(String(b.end||'9999')));
    return result;
  };
  return [...sortGroup(approvalRows),...sortGroup(normalRows)];
}
