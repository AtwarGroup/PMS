export const weekdays=['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
export const ordinals={'1':'الأول','2':'الثاني','3':'الثالث','4':'الرابع','-1':'الأخير'};
const units={daily:'يوم',weekly:'أسبوع',monthly:'شهر',yearly:'سنة'};
const DAY=86400000, OFFSET=10800000;
export const localInput=iso=>new Date(new Date(iso).getTime()+OFFSET).toISOString().slice(0,16);
export const riyadhISO=value=>new Date(value+':00+03:00').toISOString();
export function validateRule(rule,kind,interval,start){
 if(!['daily','weekly','monthly','yearly'].includes(kind)||!Number.isInteger(interval)||interval<1||interval>365)throw Error('حدد تكرارًا صحيحًا بين ١ و٣٦٥.');
 if(!Number.isFinite(new Date(start).getTime()))throw Error('حدد تاريخ بداية صحيحًا.');
 if(!['calendar','completion'].includes(rule.mode))throw Error('اختر طريقة التكرار.');
 if(rule.mode==='calendar'){
  if(kind==='weekly'||kind==='daily'&&rule.pattern==='workdays'){
   if(!Array.isArray(rule.days)||!rule.days.length||rule.days.some(x=>!Number.isInteger(x)||x<0||x>6))throw Error('اختر يومًا واحدًا على الأقل.');
  }
  if(['monthly','yearly'].includes(kind)){
   if(!['day','ordinal'].includes(rule.pattern))throw Error('اختر نمط التاريخ.');
   if(rule.pattern==='day'&&(!Number.isInteger(rule.day)||rule.day<1||rule.day>31))throw Error('اليوم يجب أن يكون بين ١ و٣١.');
   if(rule.pattern==='ordinal'&&(![1,2,3,4,-1].includes(rule.ordinal)||!Number.isInteger(rule.weekday)||rule.weekday<0||rule.weekday>6))throw Error('اختر ترتيب اليوم ويوم الأسبوع.');
   if(kind==='yearly'&&(!Number.isInteger(rule.month)||rule.month<1||rule.month>12))throw Error('اختر الشهر.');
  }
 }
 if(!['never','date','count'].includes(rule.endMode))throw Error('اختر نهاية التكرار.');
 if(rule.endMode==='date'&&(!/^\d{4}-\d{2}-\d{2}$/.test(rule.endDate)||rule.endDate<localInput(start).slice(0,10)))throw Error('تاريخ النهاية لا يسبق البداية.');
 if(rule.endMode==='count'&&(!Number.isInteger(rule.endCount)||rule.endCount<1||rule.endCount>10000))throw Error('عدد المهام يجب أن يكون بين ١ و١٠٠٠٠.');
 return rule;
}
export function nextOccurrence(rule,kind,interval,start,after){
 const anchor=new Date(new Date(start).getTime()+OFFSET), boundary=new Date(new Date(after).getTime()+OFFSET);
 const time=anchor.getUTCHours()*3600000+anchor.getUTCMinutes()*60000+anchor.getUTCSeconds()*1000;
 const base=Date.UTC(anchor.getUTCFullYear(),anchor.getUTCMonth(),anchor.getUTCDate());
 let candidate;
 if(['monthly','yearly'].includes(kind)){
  const anchorMonth=anchor.getUTCFullYear()*12+anchor.getUTCMonth(), step=interval*(kind==='yearly'?12:1);
  let month=kind==='yearly'?anchor.getUTCFullYear()*12+rule.month-1:anchorMonth;
  const current=boundary.getUTCFullYear()*12+boundary.getUTCMonth();
  month+=Math.max(0,Math.floor((current-month)/step))*step;
  for(let i=0;i<4;i++,month+=step){
   const year=Math.floor(month/12),m=month%12,last=new Date(Date.UTC(year,m+1,0)).getUTCDate();
   let day=Math.min(rule.day||anchor.getUTCDate(),last);
   if(rule.pattern==='ordinal'){
    const firstDow=new Date(Date.UTC(year,m,1)).getUTCDay();
    day=rule.ordinal===-1?last-(new Date(Date.UTC(year,m,last)).getUTCDay()-rule.weekday+7)%7:1+(rule.weekday-firstDow+7)%7+7*(rule.ordinal-1);
   }
   candidate=Date.UTC(year,m,day)+time;
   if(candidate>=anchor.getTime()&&candidate>boundary.getTime())break;
  }
 }else{
  let date=Math.max(base,Date.UTC(boundary.getUTCFullYear(),boundary.getUTCMonth(),boundary.getUTCDate()));
  const weekBase=base-anchor.getUTCDay()*DAY;
  for(let i=0;i<=interval*7+7;i++,date+=DAY){
   const day=new Date(date).getUTCDay(),diff=Math.round((date-base)/DAY);
   const match=kind==='weekly'?Math.floor((date-weekBase)/DAY/7)%interval===0&&rule.days.includes(day):rule.pattern==='workdays'?rule.days.includes(day):diff%interval===0;
   if(match&&date+time>boundary.getTime()){candidate=date+time;break;}
  }
 }
 if(candidate===undefined)return null;
 const iso=new Date(candidate-OFFSET).toISOString();
 if(rule.endMode==='date'&&localInput(iso).slice(0,10)>rule.endDate)return null;
 return iso;
}
export function previewDates(rule,kind,interval,start,count=3,created=0,from=null){
 if(rule.mode==='completion')return [];
 const dates=[];let after=new Date(Math.max(new Date(start).getTime(),from?new Date(from).getTime():0)-1000).toISOString();
 for(let i=0;i<count;i++){
  if(rule.endMode==='count'&&created+i>=rule.endCount)break;
  const date=nextOccurrence(rule,kind,interval,start,after);if(!date)break;
  dates.push(date);after=date;
 }
 return dates;
}
export function ruleSummary(rule,kind,interval){
 if(!rule)return `كل ${interval===1?'':interval+' '}${units[kind]}`;
 let text=rule.mode==='completion'?`إنشاء مهمة بعد ${interval} ${units[kind]} من الاعتماد النهائي للسابقة`:`كل ${interval} ${units[kind]}`;
 if(rule.mode==='calendar'){
  if(kind==='weekly'||kind==='daily'&&rule.pattern==='workdays')text=(kind==='daily'?'أيام العمل المحددة':text)+': '+rule.days.map(x=>weekdays[x]).join('، ');
  if(kind==='monthly'||kind==='yearly')text+='، '+(rule.pattern==='ordinal'?`${weekdays[rule.weekday]} ${ordinals[rule.ordinal]}`:`يوم ${rule.day} (آخر يوم إذا كان الشهر أقصر)`)+(kind==='yearly'?` من الشهر ${rule.month}`:'');
 }
 return text+(rule.endMode==='count'?`، حتى إنشاء ${rule.endCount} مهمة إجمالًا`:rule.endMode==='date'?`، حتى ${rule.endDate}`:'، دون تاريخ نهاية');
}
