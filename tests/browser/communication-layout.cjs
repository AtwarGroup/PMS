// Real HTML/styles, synthetic content, no backend or external requests.
const {chromium}=require(process.env.ATWAR_PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.ATWAR_CHROMIUM_PATH?{executablePath:process.env.ATWAR_CHROMIUM_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage']});try{
  const page=await browser.newPage();
  await page.route('**/*',route=>{
    const u=new URL(route.request().url()),f=path.resolve(root,'.'+decodeURIComponent(u.pathname));
    if(u.hostname!=='127.0.0.1'||!f.startsWith(root+path.sep)||!fs.existsSync(f)||!fs.statSync(f).isFile())return route.fulfill({body:'',contentType:'text/javascript'});
    let body=fs.readFileSync(f);
    if(f.endsWith('.html'))body=Buffer.from(body.toString().replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,t=>/shell-components.js|ui-feedback.js/.test(t)?t:''));
    if(/\.m?js$/.test(f)&&!/shell-components.js|ui-feedback.js|mobile-experience.mjs|systems-config.js/.test(f))return route.fulfill({body:'',contentType:'text/javascript'});
    return route.fulfill({body,contentType:f.endsWith('.html')?'text/html':f.endsWith('.css')?'text/css':'text/javascript'});
  });
  for(const width of [1440,1024,390]){
    await page.setViewportSize({width,height:540});await page.goto('http://127.0.0.1:8765/communication/index.html');
    await page.evaluate(()=>{
      document.body.classList.add('communication-page');
      document.querySelector('#identity').textContent='حساب اختبار';document.querySelector('#connection').textContent='متصل';
      document.querySelector('#conversations').innerHTML='<button class="conversation selected"><span class="avatar">ف</span><span class="conversation-copy"><strong>فريق اختبار</strong><small>متابعة الأعمال</small></span></button>';
      document.querySelector('#chatHead').innerHTML='<button class="mobile-back">‹</button><span class="avatar">ف</span><div class="chat-heading"><h2>فريق اختبار</h2><small>محادثة اختبار</small></div><button id="showDetails">التفاصيل</button><nav class="conversation-tabs"><button aria-selected="true">المحادثة</button><button>الملفات</button></nav>';
      document.querySelector('#messages').innerHTML='<div class="day-separator">اليوم</div><article class="message mine"><span class="avatar">م</span><div class="message-content"><div class="message-meta"><strong>حساب اختبار</strong><time>10:00</time></div><p class="message-body">رسالة عربية للاختبار</p></div></article><article class="message"><span class="avatar">ف</span><div class="message-content"><div class="message-meta"><strong>فريق اختبار</strong></div><p class="message-body">رسالة طويلة للتحقق من التفاف النص وإمكانية قراءة الرسائل على الكمبيوتر والجوال دون تمرير أفقي.</p></div></article>';
      document.querySelector('#layout').classList.add('chat-open');
    });
    const state=await page.evaluate(()=>{const r=document.querySelector('#composer').getBoundingClientRect(),s=getComputedStyle(document.querySelector('#messageInput'));return {overflow:document.documentElement.scrollWidth>innerWidth+2,bottom:r.bottom,width:r.width,resize:s.resize,font:parseFloat(s.fontSize)};});
    assert(!state.overflow,JSON.stringify(state));assert(state.bottom<=542&&state.width>150,JSON.stringify(state));assert.equal(state.resize,'none');assert(state.font>=14);
    assert(await page.getByRole('textbox',{name:'نص الرسالة'}).isVisible());assert(await page.getByRole('button',{name:'إرفاق ملف',exact:true}).isVisible());
    if(width===390){await page.evaluate(()=>document.querySelector('#layout').classList.remove('chat-open'));assert(await page.locator('#conversationSide').isVisible());}
  }
  console.log('PASS communication desktop/tablet/mobile: readable input, visible composer, mobile list, no horizontal overflow');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1)});
