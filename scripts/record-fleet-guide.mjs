// Reproducible training walkthrough: isolated synthetic database, never production.
import {chromium,expect} from '@playwright/test';
import {startPreview} from './fleet-preview.mjs';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
const output=path.resolve(process.argv[2]||'test-results/fleet-training');
await mkdir(output,{recursive:true});
const app=await startPreview();let browser;const frames=[];
try{
 browser=await chromium.launch({headless:true,executablePath:process.env.FLEET_CHROMIUM_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage',...JSON.parse(process.env.FLEET_CHROMIUM_ARGS||'[]')]});
 const p=await browser.newPage({viewport:{width:1280,height:900}});
 await p.route('**/*',route=>route.request().url().startsWith(app.url)||/^(data:|blob:)/.test(route.request().url())?route.continue():route.abort());
 const shot=async(title,explanation,duration=7)=>{
  await p.evaluate(({title,explanation})=>{
   document.getElementById('trainingCaption')?.remove();
   const caption=document.createElement('div');caption.id='trainingCaption';caption.dir='rtl';
   Object.assign(caption.style,{position:'fixed',bottom:'0',left:'0',right:'0',background:'#0b2545',color:'white',padding:'18px 32px',zIndex:'2147483647',fontFamily:'Arial,sans-serif',boxSizing:'border-box',borderTop:'4px solid #60a5fa',lineHeight:'1.7'});
   const heading=document.createElement('b');heading.textContent=title;heading.style.fontSize=innerWidth<700?'18px':'23px';const text=document.createElement('div');text.textContent=explanation;text.style.fontSize=innerWidth<700?'16px':'20px';caption.append(heading,text);(document.querySelector('dialog[open]')||document.body).append(caption);
  },{title,explanation});
  const file=path.join(output,`step-${String(frames.length+1).padStart(2,'0')}.png`);
  await p.screenshot({path:file});await p.evaluate(()=>document.getElementById("trainingCaption")?.remove());frames.push({file,duration,title});
 };
 const as=async(actor)=>{await p.goto(app.url+'/fleet/index.html?qa='+actor);await expect(p.locator('#fleetStatus')).toHaveText('');};
 const open=async(actor)=>{await as(actor);await p.locator('[data-tab=requests]').click();await p.locator('#requestRows tr').filter({hasText:'صيانة تعليمية للسيارة'}).getByRole('button',{name:'عرض الطلب'}).click();};
 const action=async(name,fill)=>{await p.locator('[data-action='+name+']').click();if(fill)await fill(p.locator('#actionForm'));await p.locator('#actionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();await expect(p.locator('#fleetDialog')).not.toBeVisible();};
 const pdf={name:'training-quote.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\nSYNTHETIC TRAINING FILE')};
 await as('driver');
 await shot('إدارة الأسطول — دليل عملي','عرض تدريبي ببيانات وهمية · بدون صوت · من الطلب إلى الإغلاق التلقائي',8);
 await shot('1. الموظف: لوحة المتابعة','راجع «بانتظار إجرائك» ثم اختر «طلب صيانة جديد». لكل مستخدم صلاحيات محددة.');
 await p.locator('#newRequest').click();
 await p.locator('[name=accountant_id]').selectOption({label:'المحاسب التجريبي'});
 await p.locator('[name=description]').fill('صيانة تعليمية للسيارة');
 await shot('2. أدخل بيانات الطلب','حدد السيارة والمحاسب، واختر صيانة أو عطل طارئ، واكتب العطل وقراءة العداد.');
 for(let i=0;i<3;i++){const q=p.locator('[data-quote]').nth(i);await q.locator('[name=supplier]').fill('ورشة تدريبية '+(i+1));await q.locator('[name=parts]').fill(String(400+i*20));await q.locator('[name=file]').setInputFiles({...pdf,name:`quote-${i+1}.pdf`});}
 await p.locator('[data-quote]').first().scrollIntoViewIfNeeded();
 await shot('3. أرفق عروضًا مستقلة','أدخل 3 عروض من موردين مختلفين وحدد العرض المختار. الأقل من 3 يحتاج اعتماد استثناء.',9);
 await p.getByRole('button',{name:'حفظ المسودة والمرفقات'}).click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 await open('driver');await shot('4. راجع ثم أرسل','حفظ المسودة لا يرسلها للاعتماد. اضغط «إرسال الطلب» بعد مراجعة العروض والمرفقات.');await action('submit');
 await open('fleet');await shot('5. مسؤول الأسطول: اعتماد الطلب الكبير','في هذا المثال المبلغ 400 ريال؛ يراجع مسؤول الأسطول الطلب قبل صرف العهدة.');await action('approve');
 await open('accountant');await p.locator('[data-action=confirm_advance]').click();await p.locator('[name=reference]').fill('TRAINING-ADVANCE');await p.locator('[name=evidence]').setInputFiles(pdf);
 await shot('6. المحاسب: صرف العهدة','أدخل المرجع وأرفق إثبات الصرف. النظام يعرض المبلغ المستحق؛ ثم أكد الإجراء.');await p.locator('#actionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 await open('driver');await p.locator('[data-action=request_increase]').click();await p.locator('[name=total]').fill('450');await p.locator('[name=reason]').fill('قطع إضافية مطلوبة قبل الإصلاح');
 await shot('7. زيادة التكلفة: اطلب الاعتماد أولًا','عند الحاجة إلى زيادة، أدخل الإجمالي الجديد والسبب قبل تنفيذ الزيادة.');await p.locator('#actionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 await open('fleet');await shot('8. مسؤول الأسطول: اعتماد الزيادة','راجع مبرر الزيادة من 400 إلى 450 ريال. لا يعتمد مقدم الطلب طلبه الشخصي.');await action('approve_increase');
 await open('accountant');await shot('9. المحاسب: صرف الفرق','المستحق الآن 50 ريالًا فقط. لا يكتمل مسار الإصلاح قبل صرف الفرق المعتمد.');await action('confirm_advance',async f=>{await f.locator('[name=reference]').fill('TRAINING-EXTRA');await f.locator('[name=evidence]').setInputFiles(pdf);});
 await open('driver');await p.locator('[data-action=confirm_repair]').click();await p.locator('[name=total]').fill('420');await p.locator('[name=invoice]').setInputFiles({...pdf,name:'training-invoice.pdf'});await p.locator('[name=received]').check();
 await shot('10. الموظف: الفاتورة وتأكيد الاستلام','بعد الإصلاح أدخل الفاتورة الفعلية 420 ريالًا، وأرفقها وأكد استلام السيارة.');await p.locator('#actionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 await open('accountant');await p.locator('[data-action=settle]').click();await p.locator('[name=reference]').fill('TRAINING-REFUND');await p.locator('[name=evidence]').setInputFiles(pdf);
 await shot('11. المحاسب: استرداد المتبقي والتسوية','المصروف 450 والفاتورة 420: المتبقي 30 ريالًا. وثّق الاسترداد ثم أكد التسوية.');await p.locator('#actionForm button[type=submit]').click();await expect(p.locator('#fleetDialog')).not.toBeVisible();
 await open('accountant');await expect(p.locator('#dialogBody .fleet-tag').first()).toHaveText('مغلق');await shot('12. اكتملت الدورة','أُغلق الطلب تلقائيًا بعد التسوية. يبقى سجل الإجراءات والمرفقات للرجوع إليه.');
 await p.goto(app.url+'/fleet/user-guide.html');await p.locator('#driver').scrollIntoViewIfNeeded();await shot('المبالغ حتى 300 ريال: مسار الاستعاضة','اعتماد المدير ← الإصلاح والفاتورة ← اعتماد الأسطول ← صرف الاستعاضة ← إغلاق تلقائي.',9);
 await as('driver');await p.setViewportSize({width:390,height:844});await p.locator('#newRequest').click();await p.locator('[data-quote]').first().scrollIntoViewIfNeeded();
 await shot('من الجوال: كاميرا أو ملفات','اختر التصوير بالكاميرا أو الرفع من الجهاز. راجع الصورة قبل حفظ المرفق.',8);
 await p.setViewportSize({width:1280,height:900});await p.goto(app.url+'/fleet/user-guide.html');await p.locator('#questions').scrollIntoViewIfNeeded();await shot('الدليل متاح دائمًا داخل الأسطول','افتح «دليل الاستخدام» عند الحاجة. للمشكلات: مسؤول الأسطول أو المحاسب أو مسؤول النظام حسب الموضوع.',8);
 await writeFile(path.join(output,'frames.json'),JSON.stringify(frames,null,2));
 await writeFile(path.join(output,'frames.txt'),frames.map(x=>`file '${x.file}'\nduration ${x.duration}`).join('\n')+`\nfile '${frames.at(-1).file}'\n`);
 console.log(`Saved ${frames.length} training steps to ${output}`);
}finally{await browser?.close();await app.close();}
