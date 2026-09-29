// Render Arabic with the browser's text engine. jsPDF's text path reverses mixed
// Arabic/Latin runs in some Android PDF viewers even with a Unicode font.
const W=1240,H=1754,RIGHT=1140,LEFT=100,BOTTOM=1620;
const items=value=>Array.isArray(value)?value:[];
const label=value=>typeof value==='string'?value:(value?.text||value?.name||'');

export async function createJobAcknowledgementPdf(data){
  if(!window.jspdf?.jsPDF)throw new Error('تعذر تحميل أداة إنشاء ملف PDF.');
  await document.fonts?.load('24px Tajawal').catch(()=>{});
  const {jsPDF}=window.jspdf,doc=new jsPDF({unit:'mm',format:'a4',compress:true});doc.setLanguage?.('ar-SA');
  let canvas,ctx,y,pages=0;
  function startPage(){
    canvas=document.createElement('canvas');canvas.width=W;canvas.height=H;
    ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,W,H);
    ctx.fillStyle='#0c2347';ctx.fillRect(0,0,W,164);
    ctx.textBaseline='alphabetic';ctx.textAlign='right';ctx.direction='ltr';
    ctx.font='bold 40px Arial,sans-serif';ctx.fillStyle='#fff';ctx.fillText('ATWAR ONE',RIGHT,68);
    ctx.direction='rtl';ctx.font='32px Tajawal,Arial,sans-serif';
    ctx.fillText('إقرار الاطلاع على الوصف الوظيفي',RIGHT,119);
    y=212;
  }
  function finishPage(){
    ctx.textAlign='center';ctx.direction='rtl';ctx.font='20px Tajawal,Arial,sans-serif';
    ctx.fillStyle='#788494';ctx.fillText(`صفحة ${pages+1}`,W/2,1700);
    if(pages)doc.addPage();
    doc.addImage(canvas.toDataURL('image/jpeg',0.88),'JPEG',0,0,210,297,undefined,'FAST');
    pages++;
  }
  function space(height){if(y+height>BOTTOM){finishPage();startPage()}}
  function line(text,size=27,color='#1f314e',direction='rtl'){
    const value=String(text??'').trim();if(!value)return;
    const leading=Math.ceil(size*1.55);
    ctx.font=`${size}px Tajawal,Arial,sans-serif`;
    const max=RIGHT-LEFT;
    const words=value.split(/\s+/);let current='';const lines=[];
    for(const word of words){const next=current?`${current} ${word}`:word;
      if(ctx.measureText(next).width<=max){current=next;continue}
      if(current)lines.push(current);
      if(ctx.measureText(word).width<=max){current=word;continue}
      let chunk='';for(const character of Array.from(word)){
        if(chunk&&ctx.measureText(chunk+character).width>max){lines.push(chunk);chunk=''}chunk+=character;
      }current=chunk;
    }
    if(current)lines.push(current);
    for(const part of lines){space(leading);ctx.font=`${size}px Tajawal,Arial,sans-serif`;
      ctx.fillStyle=color;ctx.direction=direction;ctx.textAlign='right';ctx.fillText(part,RIGHT,y);y+=leading}
    y+=8;
  }
  function section(title,values){const rows=items(values).map(label).filter(Boolean);if(!rows.length)return;
    space(76);y+=15;line(title,33,'#1769e0');rows.forEach((value,index)=>line(`${index+1}. ${value}`));
  }
  startPage();
  line(`الموظف: ${data.employeeName||'—'}`,30);
  line('البريد الإلكتروني:');line(data.email||'—',25,'#1f314e','ltr');
  line(`الإدارة: ${data.department||'—'}`);
  line(`المدير المباشر: ${data.managerName||'غير محدد'}`);
  line(`المسمى الوظيفي: ${data.title||'—'}`,30);
  line(`إصدار الوصف: ${data.revision||1}`);
  line(`تاريخ ووقت الموافقة: ${new Intl.DateTimeFormat('ar-SA',{dateStyle:'long',timeStyle:'short',timeZone:'Asia/Riyadh'}).format(new Date(data.acceptedAt))}`);
  if(data.purpose){space(76);line('الغرض من الوظيفة',33,'#1769e0');line(data.purpose)}
  const content=data.content||{};
  section('المهام والمسؤوليات',content.responsibilities);
  section('الصلاحيات',content.authorities);
  section('مؤشرات الأداء',content.kpis);
  section('التقارير والمخرجات',content.reports);
  const q=content.qualifications||{};
  if(q.education||q.experience||q.skills){space(76);line('المؤهلات المطلوبة',33,'#1769e0');line(`المؤهل: ${q.education||'—'}`);line(`الخبرة: ${q.experience||'—'}`);line(`المهارات: ${q.skills||'—'}`)}
  space(76);line('نص الإقرار',33,'#1769e0');line(data.acknowledgementText||'',29);
  line(`رقم الإقرار: ${data.id||''}`,23,'#64748b');
  finishPage();
  const encoded=doc.output('datauristring').split(',')[1];
  if(encoded.length>10*1024*1024)throw new Error('حجم ملف الإقرار كبير جدًا. يرجى التواصل مع مسؤول النظام.');
  return encoded;
}
