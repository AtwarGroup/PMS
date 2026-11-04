import {money,englishDigits,quoteTotal,quoteIncludes,types,maintenanceKinds} from './fleet-model.mjs?v=20261104.1';

export function financeRequestView(detail,context){
 const r=detail.request;
 const finance=context.can_finance&&!context.is_admin&&!context.can_correct&&!context.supervised_owner_id&&r.driver_id!==context.employee_id&&(context.finance_only||r.accountant_id===context.user_id);
 const quotes=(r.quotes||[]).map((quote,index)=>({quote,index})).filter(x=>!finance||x.index===Number(r.selected_quote));
 const ids=new Set(quotes.flatMap(({quote:q})=>['parts','labor'].flatMap(k=>q[k+'_file_ids']?.length?q[k+'_file_ids']:[q[k+'_file_id']]).filter(Boolean)));
 return {finance,quotes,files:(detail.files||[]).filter(f=>!finance||!['quote','quote_parts','quote_labor'].includes(f.kind)||ids.has(f.id))};
}
const units=['','واحد','اثنان','ثلاثة','أربعة','خمسة','ستة','سبعة','ثمانية','تسعة'];
function under1000(n){
 const out=[];if(n>=100){out.push(['','مائة','مائتان','ثلاثمائة','أربعمائة','خمسمائة','ستمائة','سبعمائة','ثمانمائة','تسعمائة'][Math.floor(n/100)]);n%=100;}
 if(n>=20){const t=['','','عشرون','ثلاثون','أربعون','خمسون','ستون','سبعون','ثمانون','تسعون'][Math.floor(n/10)];out.push((n%10?units[n%10]+' و':'')+t);}
 else if(n>=10)out.push(['عشرة','أحد عشر','اثنا عشر','ثلاثة عشر','أربعة عشر','خمسة عشر','ستة عشر','سبعة عشر','ثمانية عشر','تسعة عشر'][n-10]);else if(n)out.push(units[n]);return out.join(' و');
}
function integerWords(n){const out=[];for(const [v,one,two,few]of [[1000000,'مليون','مليونان','ملايين'],[1000,'ألف','ألفان','آلاف']]){const k=Math.floor(n/v);if(k){out.push(k===1?one:k===2?two:under1000(k)+' '+(k<=10?few:one));n%=v;}}if(n)out.push(under1000(n));return out.join(' و')||'صفر';}
export function amountInWords(value){const cents=Math.round(Number(value)*100);return integerWords(Math.floor(cents/100))+' ريال سعودي'+(cents%100?' و'+integerWords(cents%100)+' هللة':'')+' فقط لا غير';}
const date=value=>value?new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Riyadh',day:'2-digit',month:'2-digit',year:'numeric'}).format(new Date(value)):'—';
// A single raster A4 page preserves the browser's Arabic shaping in every PDF viewer.
// No external PDF service receives employee or financial data.
export function canvasPDF(canvas){
 const bytes=Uint8Array.from(atob(canvas.toDataURL('image/jpeg',0.96).split(',')[1]),c=>c.charCodeAt(0));
 const enc=new TextEncoder(),chunks=[],offsets=[0];let size=0;const add=s=>{const b=typeof s==='string'?enc.encode(s):s;chunks.push(b);size+=b.length;};
 add('%PDF-1.4\n');const object=(n,s)=>{offsets[n]=size;add(`${n} 0 obj\n${s}\nendobj\n`);};
 object(1,'<< /Type /Catalog /Pages 2 0 R >>');object(2,'<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
 object(3,'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>');
 offsets[4]=size;add(`4 0 obj\n<< /Type /XObject /Subtype /Image /Width ${canvas.width} /Height ${canvas.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${bytes.length} >>\nstream\n`);add(bytes);add('\nendstream\nendobj\n');
 const stream='q 595.28 0 0 841.89 0 0 cm /Im0 Do Q';object(5,`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
 const xref=size;add('xref\n0 6\n0000000000 65535 f \n');for(let i=1;i<=5;i++)add(String(offsets[i]).padStart(10,'0')+' 00000 n \n');add(`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`);return new Blob(chunks,{type:'application/pdf'});
}
async function imageAt(path){const img=new Image();img.src=new URL(path,import.meta.url).href;await img.decode();return img;}
export async function reimbursementCanvas(data){
 const {request:r,events=[],payments=[]}=data.detail;const q=r.quotes?.[Number(r.selected_quote)];if(!q||!Number(r.invoice_total))throw Error('بيانات الاستعاضة غير مكتملة.');
 const [atwar,tirador]=await Promise.all([imageAt('../../logo.png'),imageAt('../images/tirador-logo.png')]);await document.fonts.ready;
 const canvas=document.createElement('canvas');canvas.width=1240;canvas.height=1754;const c=canvas.getContext('2d');c.fillStyle='#fff';c.fillRect(0,0,1240,1754);
 const ink='#102b4e',muted='#53657b',blue='#304394',line='#d7e1ec';const L=78,R=1162,W=R-L;
 function text(value,x,y,size=24,color=ink,align='right',bold=false){c.font=`${bold?'bold ':''}${size}px Tajawal,Arial,sans-serif`;c.direction='rtl';c.textAlign=align;c.fillStyle=color;c.fillText(englishDigits(value??'—'),x,y);}
 function wrap(value,width,size=24,maxLines=3){c.font=`${size}px Tajawal,Arial,sans-serif`;const words=englishDigits(value||'—').split(/\s+/),lines=[];let current='';for(const word of words){let next=current?current+' '+word:word;if(c.measureText(next).width>width&&current){lines.push(current);current=word;}else current=next;while(c.measureText(current).width>width){let chunk='';for(const char of current){if(c.measureText(chunk+char).width>width)break;chunk+=char;}lines.push(chunk);current=current.slice(chunk.length);}}if(current)lines.push(current);if(lines.length>maxLines){lines.length=maxLines;while(c.measureText(lines.at(-1)+'…').width>width)lines[maxLines-1]=lines.at(-1).slice(0,-1);lines[maxLines-1]+='…';}return lines;}
 function paragraph(value,x,y,width,size=24,maxLines=3){const lines=wrap(value,width,size,maxLines);lines.forEach((s,i)=>text(s,x,y+i*34,size));return lines.length*34;}
 function rule(y){c.strokeStyle=line;c.lineWidth=1;c.beginPath();c.moveTo(L,y);c.lineTo(R,y);c.stroke();}
 function section(title,y){c.fillStyle='#f1f5fa';c.fillRect(L,y,W,43);text(title,R-16,y+30,25,ink,'right',true);}
 function pair(label,value,x,y,width=500){text(label,x,y,21,muted);paragraph(value,x,y+34,width,25,2);}
 function logo(img,x,y,maxW,maxH){const k=Math.min(maxW/img.width,maxH/img.height);c.drawImage(img,x+(maxW-img.width*k)/2,y+(maxH-img.height*k)/2,img.width*k,img.height*k);}
 logo(atwar,R-260,56,260,120);logo(tirador,L,56,250,120);text('ATWAR ONE',620,103,29,blue,'center',true);text('إدارة أسطول السيارات',620,143,23,muted,'center');rule(196);
 text('طلب صرف استعاضة — صيانة سيارة',620,249,35,ink,'center',true);
 const payment=payments.filter(p=>p.kind==='reimbursement').at(-1),paid=Boolean(payment);text(paid?'تم الصرف — نسخة توثيقية':'طلب صرف — لم يتم الصرف',620,291,25,paid?'#08734c':'#9a5b08','center',true);
 text(`رقم الطلب: ${r.number}  |  إصدار البيانات: ${r.revision}`,R,337,23);text(`تاريخ النموذج: ${date(data.issued_at)}`,L,337,23,muted,'left');
 section('بيانات المستفيد والسيارة',365);pair('المستفيد',data.employee_name,R-16,440);pair('الرقم الوظيفي / الإدارة',`${data.employee_code||'—'} / ${data.department||'—'}`,L+510,440);
 pair('السيارة / اللوحة',`${data.vehicle_type||''} ${data.model||''} / ${data.plate||'—'}`,R-16,534);pair('قراءة العداد / تاريخ الطلب',`${r.odometer} كم / ${date(r.created_at)}`,L+510,534);
 section('تفاصيل الصيانة والعرض المعتمد',623);text(`${types[r.request_type]||'صيانة'}${maintenanceKinds[r.maintenance_kind]?' / '+maintenanceKinds[r.maintenance_kind]:''}`,R-16,700,23,muted);paragraph(r.description,R-16,740,W-32,25,2);text('تفاصيل الأعمال الكاملة والفاتورة محفوظة في الطلب الإلكتروني.',R-16,803,20,muted);
 paragraph(`الورشة: ${q.supplier}`,R-16,850,740,24,2);text(`الجوال: ${q.phone||'—'}`,L+16,850,23,muted,'left');
 const cols=Array.from({length:4},(_,i)=>L+W*(3.5-i)/4);['قطع الغيار','أجرة اليد','الضريبة','إجمالي العرض'].forEach((s,i)=>text(s,cols[i],906,23,muted,'center'));[quoteIncludes(q,'parts')?money(q.parts):'—',quoteIncludes(q,'labor')?money(q.labor):'—',money(q.tax),money(quoteTotal(q))].forEach((s,i)=>text(s,cols[i],950,27,ink,'center',true));rule(975);
 c.fillStyle='#edf5f2';c.fillRect(L,997,W,110);text(`إجمالي الفاتورة: ${money(r.invoice_total)} ر.س`,R-20,1039,25);text(`مبلغ الاستعاضة: ${money(r.invoice_total)} ر.س`,R-20,1081,29,ink,'right',true);
 paragraph(amountInWords(r.invoice_total),R-16,1150,W-32,24,2);
 const approvals=events.filter(e=>['approve','approve_exception','approve_increase','confirm_repair'].includes(e.action));text('الإجراءات المسجلة بالنظام',R-16,1234,23,ink,'right',true);paragraph(approvals.map(e=>`${e.action==='confirm_repair'?'تأكيد الإصلاح':'اعتماد'}: ${e.actor_name} (${date(e.created_at)})`).join(' • ')||'راجع سجل إجراءات الطلب',R-16,1273,W-32,21,2);
 section('الاعتمادات الورقية للصرف',1353);
 const signatures=[['إعداد المحاسب',data.accountant_name],['اعتماد رئيس الحسابات',data.chief_accountant_name],['اعتماد المدير المالي',data.finance_manager_name]];
 signatures.forEach(([title,name],i)=>{const x=R-18-i*(W/3);text(title,x,1440,24,ink,'right',true);paragraph(name||'الاسم: __________________',x,1484,W/3-32,23,1);text('التوقيع: __________________',x,1536,22,muted);text('التاريخ: __________________',x,1579,22,muted);});
 rule(1610);if(paid)paragraph(`توثيق الصرف: ${money(payment.amount)} ر.س | ${date(payment.created_at)} | المرجع: ${payment.reference}`,R,1643,W,16,2);else text('يُسلّم النموذج لموظف البنك للصرف بعد استكمال التوقيعات.',620,1651,21,muted,'center');text(`ATWAR ONE • FLEET-${r.number} • صفحة 1 من 1`,620,1698,19,muted,'center');return canvas;
}
export async function downloadReimbursementPDF(data){const canvas=await reimbursementCanvas(data);const url=URL.createObjectURL(canvasPDF(canvas));const a=document.createElement('a');a.href=url;a.download=`fleet-reimbursement-${data.detail.request.number}.pdf`;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);}
