
(function(){
  const shellScript=document.currentScript;
  const assetRoot=new URL('../',shellScript?.src||location.href);
  if(!document.querySelector('link[data-atwar-design-system]')){
    const style=document.createElement('link');style.rel='stylesheet';style.dataset.atwarDesignSystem='1';style.href=new URL('css/design-system.css?v=2.5.8',assetRoot).href;document.head.append(style);
  }
  const mobileStyle=document.createElement('link');mobileStyle.rel='stylesheet';mobileStyle.href=new URL('css/mobile-experience.css?v=2',assetRoot).href;document.head.append(mobileStyle);
  const startMobile=()=>import(new URL('js/mobile-experience.mjs?v=3',assetRoot).href).then(m=>m.startMobileExperience()).catch(e=>console.error('Mobile experience could not load',e));
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',startMobile,{once:true});else startMobile();
  // Reuse and move the existing stylesheet after module CSS; never load two versions.
  const loadCanonicalTheme=()=>{
    const href=new URL('css/app-theme.css?v=notifications-20261101',assetRoot).href;
    const matches=[...document.querySelectorAll('link[rel="stylesheet"]')].filter(link=>new URL(link.href,location.href).pathname===new URL(href).pathname);
    const style=matches.shift()||document.createElement('link');
    for(const duplicate of matches)duplicate.remove();
    style.rel='stylesheet';style.dataset.atwarAppTheme='1';
    if(style.href!==href)style.href=href;
    document.head.append(style);
  };
  if(!location.pathname.includes('/communication/')&&!location.pathname.includes('/communication-trial/')){import(new URL('js/communication-global.mjs?v=20261027-bfcache',assetRoot).href).then(m=>m.startCommunicationAlerts()).catch(()=>{});}
  const loadCanonicalTypography=()=>{
    const style=document.querySelector('link[data-atwar-typography]')||document.createElement('link');
    style.rel='stylesheet';style.dataset.atwarTypography='1';
    const href=new URL('css/typography.css?v=2.8.4',assetRoot).href;
    if(style.href!==href)style.href=href;
    document.head.append(style);
  };
  const loadVisualContract=()=>{loadCanonicalTheme();loadCanonicalTypography()};
  // Start the shared CSS request during parsing; reapply cascade order after module CSS.
  // This only loads presentation assets and never reveals authenticated content.
  loadVisualContract();
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',loadVisualContract,{once:true});
  else loadVisualContract();
  if(!document.querySelector('link[rel~="icon"]')){
    const icon=document.createElement('link');icon.rel='icon';icon.type='image/svg+xml';
    icon.href=new URL('../../favicon.svg',document.currentScript?.src||location.href).href;
    document.head.append(icon);
  }
  function depth(){
    const nestedModules=['tasks','completed','team','profile','workspace','follow-up','notifications','search','admin','approvals','organization','job-library','my-day','recurring','policies','projects','communication','fleet','recruitment','it-support'];
    return nestedModules.some(name=>location.pathname.includes('/'+name+'/'))?'../':'';
  }
  function getSession(){
    try{return JSON.parse(localStorage.getItem('atwarSession')||'null')}catch{return null}
  }
  const rank={employee:1,manager:2,admin:3};
  const soundSetting='atwar-notification-sound';
  const soundTypes={IT_SUPPORT:'new',FLEET_WORKFLOW:'new',FLEET_HANDOVER:'new',RECRUITMENT:'new',JOB_DESCRIPTION_ASSIGNED:'new',assigned:'new',TASK_ASSIGNED:'new',TASK_DELEGATED:'new',approved:'approved',TASK_APPROVED:'approved',completed:'completed',TASK_COMPLETED:'completed'};
  let audioContext=null;
  window.atwarNotificationSound={
    enabled:()=>localStorage.getItem(soundSetting)!=='off',
    setEnabled(value){localStorage.setItem(soundSetting,value?'on':'off')},
    observe(rows,userId){
      if(!userId)return;
      const key=`atwar-sound-seen-${userId}`;
      const previous=sessionStorage.getItem(key);
      const newest=rows.reduce((max,row)=>Math.max(max,new Date(row.created_at||row.createdAt||0).getTime()||0),0);
      if(previous!==null&&this.enabled()&&document.visibilityState==='visible'){
        const fresh=rows.filter(row=>!row.read_at&&!row.read&&new Date(row.created_at||row.createdAt||0).getTime()>Number(previous));
        const kind=fresh.map(row=>soundTypes[row.type]).find(type=>type==='approved'||type==='completed')||fresh.map(row=>soundTypes[row.type]).find(Boolean);
        if(kind)this.play(kind);
      }
      sessionStorage.setItem(key,String(Math.max(Number(previous)||0,newest,Date.now()-(previous===null?0:86400000))));
    },
    play(kind){
      try{
        const Context=window.AudioContext||window.webkitAudioContext;
        if(!Context)return;
        audioContext ||= new Context();
        if(audioContext.state==='suspended'){void audioContext.resume();return}
        const notes=kind==='approved'?[660,880]:kind==='completed'?[523,659,784]:[660,784];
        notes.forEach((frequency,index)=>{
          const start=audioContext.currentTime+index*.12;
          const oscillator=audioContext.createOscillator(),gain=audioContext.createGain();
          oscillator.type='sine';oscillator.frequency.value=frequency;
          gain.gain.setValueAtTime(.0001,start);gain.gain.exponentialRampToValueAtTime(.035,start+.018);
          gain.gain.exponentialRampToValueAtTime(.0001,start+.19);
          oscillator.connect(gain);gain.connect(audioContext.destination);oscillator.start(start);oscillator.stop(start+.2);
        });
      }catch(error){console.warn('Notification sound unavailable:',error)}
    }
  };
  const unlockNotificationAudio=()=>{
    if(!window.atwarNotificationSound.enabled())return;
    try{
      const Context=window.AudioContext||window.webkitAudioContext;
      if(Context){audioContext ||= new Context();if(audioContext.state==='suspended')void audioContext.resume();document.removeEventListener('pointerdown',unlockNotificationAudio)}
    }catch{}
  };
  document.addEventListener('pointerdown',unlockNotificationAudio);

  class AtwarSidebar extends HTMLElement{
    connectedCallback(){
      const d=depth(),requestedActive=this.getAttribute('active')||'',s=getSession();
      const inTaskModule=/\/(tasks|completed|recurring)\//.test(location.pathname);
      const active=inTaskModule?'tasks':requestedActive;
      const nav=(key,path,icon,label,min='employee')=>{
        if(s && (rank[s.role]||0)<(rank[min]||0))return '';
        const unit={notes:'workspace',jobLibrary:'job_library'}[key]||key;
        if(window.AtwarModules?.context&&!window.AtwarModules.allowed(unit)&&!['home','profile'].includes(key))return '';
        return `<a data-notification-module="${unit}" ${key==='fleet'?'data-module="fleet"':''} class="${active===key?'active':''}" href="${d}${path}">
          <i data-lucide="${icon}"></i><span>${label}</span></a>`;
      };
      this.innerHTML=`<aside class="atwar-sidebar">
        <div class="atwar-brand"><h1>ATWAR ONE</h1><p>نظام إدارة الأداء المؤسسي</p></div>
        <nav class="atwar-nav">
          ${nav('home','home.html','home','الرئيسية')}
          ${nav('tasks','tasks/index.html','square-check-big','المهام')}
          ${nav('communication','communication/index.html','messages-square','التواصل')}
          ${nav('projects','projects/index.html','chart-gantt','إدارة المشاريع')}
          ${nav('fleet','fleet/index.html','truck','إدارة الأسطول')}
          ${nav('recruitment','recruitment/index.html','user-round-plus','التوظيف')}
          ${nav('it_support','it-support/index.html','monitor-cog','دعم تقنية المعلومات')}
          ${nav('notes','workspace/index.html','notebook-tabs','مساحتي')}
          ${nav('employees','admin/employees.html','contact-round','الموظفون')}
          ${nav('jobLibrary','job-library/index.html','library-big','مكتبة الوظائف','manager')}
          ${nav('policies','policies/index.html','book-open-check','مكتبة السياسات')}
          ${nav('profile','profile/index.html?view=job','badge-check','ملفي الوظيفي')}
        </nav>
        <div class="atwar-spacer"></div>
        <div class="atwar-side-section">
          <a class="atwar-side-link" href="${d}landing.html"><i data-lucide="layout-grid"></i><span>بوابة الأنظمة</span></a>
          ${s?.role==='admin'?`<a class="atwar-side-link ${active==='admin'?'active':''}" href="${d}admin/index.html"><i data-lucide="settings"></i><span>إدارة النظام</span></a>`:''}
          <div class="atwar-side-link"><i data-lucide="circle-help"></i><span>الدعم والمساعدة</span></div>
          <button type="button" class="atwar-side-link atwar-shell-logout"><i data-lucide="log-out"></i><span>تسجيل خروج</span></button>
        </div>
      </aside>`;
      this.querySelector('.atwar-shell-logout')?.addEventListener('click',()=>{
        if(typeof window.atwarLogout==='function')window.atwarLogout();
        else if(typeof window.logoutUser==='function')window.logoutUser();
        else location.href=d+'landing.html';
      });
      window.lucide?.createIcons();
    }
  }

  class AtwarHeader extends HTMLElement{
    connectedCallback(){
      const currentPath=location.pathname;
      const d=depth(),mode=this.getAttribute('mode')||'default',s=getSession();
      const taskNavActive=key=>{
        const completedScope=/\/tasks\//.test(currentPath)&&String(new URLSearchParams(location.search).get('scope')||'').toUpperCase()==='COMPLETED';
        if(key==='tasks')return /\/tasks\//.test(currentPath)&&!currentPath.endsWith('/executive.html')&&!completedScope;
        if(key==='completed')return /\/completed\//.test(currentPath)||completedScope;
        if(key==='recurring')return /\/recurring\//.test(currentPath);
        if(key==='executive')return currentPath.endsWith('/executive.html');
        return false;
      };
      const recurringAllowed=!s || ['manager','admin'].includes(s.role);
      const executiveAllowed=!s || s.role==='admin'||(s.permissions||[]).includes('tasks.read_all');
      const taskModuleOpen=/\/(tasks|completed|recurring)\//.test(currentPath);
      const supportPurchase=/\/it-support\/purchases\.html$/.test(currentPath),supportModuleOpen=/\/it-support\//.test(currentPath),supportArchive=String(new URLSearchParams(location.search).get('scope')||'').toUpperCase()==='COMPLETED';
      const taskNav=supportModuleOpen?`<nav class="atwar-header-task-nav atwar-tabs" aria-label="قائمة دعم تقنية المعلومات"><a class="${!supportArchive&&!supportPurchase?'active':''}" href="${d}it-support/index.html"><i data-lucide="monitor-cog"></i><span>الدعم</span></a><a class="${supportPurchase&&!supportArchive?'active':''}" href="${d}it-support/purchases.html"><i data-lucide="shopping-cart"></i><span>الشراء التقني</span></a><a class="${supportArchive?'active':''}" href="${d}it-support/${supportPurchase?'purchases.html':'index.html'}?scope=COMPLETED"><i data-lucide="archive"></i><span>الأرشيف</span></a></nav>`:taskModuleOpen?`
        <nav class="atwar-header-task-nav atwar-tabs" aria-label="قائمة المهام">
          <a class="${taskNavActive('tasks')?'active':''}" href="${d}tasks/index.html"><i data-lucide="square-check-big"></i><span>النشطة</span></a>
          <a class="${taskNavActive('completed')?'active':''}" href="${d}tasks/index.html?scope=COMPLETED"><i data-lucide="archive"></i><span>المكتملة</span></a>
          ${recurringAllowed?`<a class="${taskNavActive('recurring')?'active':''}" href="${d}recurring/index.html"><i data-lucide="repeat-2"></i><span>الدورية</span></a>`:''}
          ${executiveAllowed?`<a class="${taskNavActive('executive')?'active':''}" href="${d}tasks/executive.html"><i data-lucide="scan-eye"></i><span>الاطلاع التنفيذي</span></a>`:''}
        </nav>`:'';
      const taskTools=mode==='tasks'?`
        <button type="button" id="addTaskButton" onclick="showQuickAdd()" class="atwar-task-add"><i data-lucide="plus"></i><span>إضافة مهمة</span></button>
        <div class="atwar-task-notification-wrap">
          <button id="notificationButton" data-global-notification-button type="button" class="atwar-icon-btn" title="الإشعارات">
            <i data-lucide="bell"></i><span id="notificationBadge" data-global-notification-badge class="hidden atwar-notification-badge">0</span>
          </button>
          <div id="notificationPanel" data-global-notification-panel class="hidden atwar-task-notification-panel">
            <div class="atwar-notification-head"><b>الإشعارات</b><button type="button" data-sound-toggle aria-label="تبديل صوت الإشعارات"></button><button type="button" data-global-mark-read>تحديد الكل كمقروء</button></div>
            <div id="notificationList" data-global-notification-list class="atwar-notification-list"></div><a class="atwar-notification-history" href="${d}notifications/index.html">عرض جميع الإشعارات</a>
          </div>
        </div>
        <label id="importLabel" for="importFile" class="atwar-icon-btn" title="رفع Excel"><i data-lucide="upload"></i></label>
        <button type="button" onclick="exportToExcel()" class="atwar-icon-btn" title="تنزيل Excel"><i data-lucide="download"></i></button>
        <a href="user-guide.html" target="_blank" class="atwar-icon-btn" title="دليل المستخدم"><i data-lucide="book-open"></i></a>
        <input id="importFile" type="file" accept=".xlsx" class="hidden" onchange="handleImport(event)">
      `:`<div class="atwar-task-notification-wrap" data-global-notification-wrap>
          <button type="button" class="atwar-bell" title="الإشعارات" data-global-notification-button>
            <i data-lucide="bell"></i><span class="atwar-badge hidden" data-global-notification-badge>0</span>
          </button>
          <div class="atwar-task-notification-panel hidden" data-global-notification-panel>
            <div class="atwar-notification-head"><b>الإشعارات</b><button type="button" data-sound-toggle aria-label="تبديل صوت الإشعارات"></button><button type="button" data-global-mark-read>تحديد الكل كمقروء</button></div>
            <div class="atwar-notification-list" data-global-notification-list><div style="padding:24px;text-align:center;font-size:10px;color:#94a3b8">جاري تحميل الإشعارات...</div></div>
            <a href="${d}notifications/index.html" style="display:block;padding:10px 14px;text-align:center;font-size:10px;font-weight:900;color:#2563eb;text-decoration:none;border-top:1px solid #eef2f7">عرض جميع الإشعارات</a>
          </div>
        </div>`;

      this.innerHTML=`<style>
        .atwar-topbar{flex-wrap:nowrap}
        .atwar-account-wrap{position:relative;flex:0 0 auto}
        .atwar-account-trigger{border:0;background:transparent;color:inherit;cursor:pointer;padding:4px 6px!important;min-height:44px!important;border-radius:12px!important}
        .atwar-account-trigger:hover,.atwar-account-trigger[aria-expanded="true"]{background:rgba(255,255,255,.08)}
        .atwar-account-menu{position:absolute;left:0;top:calc(100% + 10px);width:280px;background:#fff;color:#24364b;border:1px solid #dfe7f0;border-radius:16px;box-shadow:0 22px 55px rgba(15,23,42,.22);overflow:hidden;z-index:1300;text-align:right}
        .atwar-account-summary{display:flex;align-items:center;gap:11px;padding:15px;border-bottom:1px solid #edf2f7;background:#f8fafc}
        .atwar-account-summary .atwar-avatar{background:#e8f2ff!important;color:#1769e0!important}
        .atwar-account-copy{min-width:0}.atwar-account-copy b,.atwar-account-copy span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.atwar-account-copy b{font-size:12px}.atwar-account-copy span{font-size:10px;color:#64748b;margin-top:3px}
        .atwar-account-links{padding:7px}.atwar-account-links a,.atwar-account-links button{width:100%;min-height:40px!important;display:flex;align-items:center;gap:10px;padding:9px 11px!important;border:0;background:transparent;color:#334155;text-decoration:none;font-size:11px!important;font-weight:800;text-align:right;cursor:pointer;border-radius:9px!important}
        .atwar-account-links a:hover,.atwar-account-links button:hover{background:#f1f5f9}.atwar-account-links svg{width:16px;height:16px;color:#64748b}.atwar-account-links .danger{color:#dc2626;border-top:1px solid #edf2f7;margin-top:5px;border-radius:0!important}.atwar-account-links .danger svg{color:#dc2626}
      </style>
      <header class="atwar-topbar ${mode==='tasks'?'atwar-task-header':''}">
        <div class="atwar-top-brand">
          <div class="atwar-brand-mark"></div>
          <div class="atwar-org-title">
              <h2>نظام إدارة الأداء المؤسسي</h2>
              <p>مؤسسة أطوار للتجارة</p>
            </div>
          <div class="atwar-pm-label">Performance Management<br>System</div>
        </div>
        ${mode==='tasks'?`<span id="pageSubtitle" class="hidden"></span>`:''}
        <div class="atwar-top-actions ${mode==='tasks'?'atwar-task-tools':''}">
          <div class="atwar-search"><i data-lucide="search"></i>
            <input ${mode==='tasks'?'id="taskHeaderSearch"':'data-global-search'} type="text" placeholder="${mode==='tasks'?'البحث في المهام...':'ابحث في المهام، الموظفين، المستندات...'}">
          </div>
          ${taskTools}
          ${mode==='tasks'?`<span id="saveStatus" class="atwar-task-save-status">☁️ تم الحفظ</span>`:''}
          <div class="atwar-account-wrap">
            <button type="button" class="atwar-user atwar-account-trigger" aria-haspopup="menu" aria-expanded="false" title="الحساب الشخصي">
              <div><div class="atwar-user-name" data-user-name>المستخدم</div><div class="atwar-user-role" data-user-title></div></div>
              <div class="atwar-avatar">أ</div>
              <i data-lucide="chevron-down"></i>
            </button>
            <div class="atwar-account-menu hidden" role="menu">
              <div class="atwar-account-summary">
                <div class="atwar-avatar">أ</div>
                <div class="atwar-account-copy"><b data-user-name>المستخدم</b><span data-user-title>المسمى الوظيفي</span></div>
              </div>
              <div class="atwar-account-links">
                <a href="${d}profile/index.html?view=profile" role="menuitem"><i data-lucide="circle-user-round"></i><span>الملف التعريفي</span></a>
                <a href="${d}profile/security.html" role="menuitem"><i data-lucide="key-round"></i><span>تغيير كلمة المرور</span></a>
                <button type="button" class="danger atwar-account-logout" role="menuitem"><i data-lucide="log-out"></i><span>تسجيل الخروج</span></button>
              </div>
            </div>
          </div>
          ${mode==='tasks'?`<span id="currentUserBadge" class="hidden"></span>`:''}
        </div>
      </header>`;
      if(s){
        this.querySelectorAll('[data-user-name]').forEach(x=>x.textContent=s.name||s.email||'المستخدم');
        this.querySelectorAll('[data-user-title]').forEach(x=>x.textContent=s.title||'');
        const av=this.querySelector('.atwar-avatar');
        if(av)av.textContent=(s.name||s.email||'م').trim().charAt(0);
      }
      window.lucide?.createIcons();
      const accountTrigger=this.querySelector('.atwar-account-trigger');
      const soundToggle=this.querySelector('[data-sound-toggle]');
      if(soundToggle){
        const updateLabel=()=>{soundToggle.textContent=window.atwarNotificationSound.enabled()?'🔊 الصوت مفعّل':'🔇 الصوت مكتوم'};
        updateLabel();
        soundToggle.addEventListener('click',()=>{window.atwarNotificationSound.setEnabled(!window.atwarNotificationSound.enabled());updateLabel()});
      }
      // Page navigation belongs with the page heading, outside the global header.
      const mountTaskNavigation=()=>{
        const heading=document.querySelector('main .task-suite-hero');
        if(!taskNav||!heading||heading.parentElement.querySelector('.atwar-header-task-nav'))return;
        heading.insertAdjacentHTML('afterend',taskNav);
        const nav=heading.nextElementSibling;
        nav.querySelector('a.active')?.setAttribute('aria-current','page');
        window.lucide?.createIcons();
      };
      if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mountTaskNavigation,{once:true});
      else mountTaskNavigation();
      const accountMenu=this.querySelector('.atwar-account-menu');
      accountTrigger?.addEventListener('click',event=>{
        event.preventDefault();event.stopPropagation();
        const open=accountMenu?.classList.toggle('hidden')===false;
        accountTrigger.setAttribute('aria-expanded',String(open));
      });
      accountMenu?.addEventListener('click',event=>event.stopPropagation());
      document.addEventListener('click',()=>{accountMenu?.classList.add('hidden');accountTrigger?.setAttribute('aria-expanded','false')});
      this.querySelector('.atwar-account-logout')?.addEventListener('click',()=>{
        if(typeof window.atwarLogout==='function')window.atwarLogout();
        else if(typeof window.logoutUser==='function')window.logoutUser();
        else location.href=d+'landing.html';
      });
      {
        const initNotifications=()=>window.atwarInitGlobalNotifications?.(this,d);
        if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',initNotifications,{once:true});
        else initNotifications();
      }
    }
  }



  window.atwarOpenNotificationRecord=async function(sb,row,depthPrefix='',onError=()=>{}){
    if(!row)return false;
    const markRead=async()=>{
      const ids=Array.isArray(row.unread_ids)?row.unread_ids:(row.read_at?[]:[row.id]);
      for(let i=0;i<ids.length;i+=100){const {error}=await sb.from('notifications').update({read_at:new Date().toISOString()}).in('id',ids.slice(i,i+100));if(error){onError('تعذر تحديث حالة الإشعار.');return false;}}
      window.atwarNotifyReadChange?.();return true;
    };
    if(row.type==='RECRUITMENT'){if(!await markRead())return false;location.href=depthPrefix+'recruitment/index.html';return true;}
    if(row.type==='IT_SUPPORT'){const {data,error}=await sb.rpc('it_support_notification_open',{p_id:row.id});if(error||!data){onError('الإشعار أو الطلب غير متاح لك حاليًا.');return false;}if(!await markRead())return false;location.href=depthPrefix+'it-support/'+(data.purchase?'purchases.html':'index.html')+(data.ticket_id?'?request='+encodeURIComponent(data.ticket_id):'');return true;}
    if(['FLEET_WORKFLOW','FLEET_HANDOVER'].includes(row.type)){const {data,error}=await sb.rpc('fleet_workflow_notification_open',{p_notification:row.id});if(error||!data){onError('السجل غير متاح لك حاليًا.');return false;}if(!await markRead())return false;const query=data.request_id?'request='+encodeURIComponent(data.request_id):'handover='+encodeURIComponent(data.handover_id);location.href=depthPrefix+'fleet/index.html?'+query;return true;}
    if(row.type==='FLEET_DOCUMENT'){const {data,error}=await sb.rpc('fleet_document_open',{p_notification:row.id});if(error||!data){onError('الوثيقة غير متاحة لك حاليًا.');return false;}if(!await markRead())return false;location.href=depthPrefix+'fleet/index.html?view=documents&vehicle='+encodeURIComponent(data);return true;}
    if(row.type==='communication'||row.type==='communication_trial'){
      const {data,error}=await sb.rpc(row.type==='communication'?'communication_notification_open':'communication_trial_notification_open',{p_id:row.id});
      if(error||!data){onError('المحادثة غير متاحة لك حاليًا.');return false;}
      if(!await markRead())return false;location.href=depthPrefix+(row.type==='communication'?'communication/':'communication-trial/')+'?conversation='+encodeURIComponent(data.conversation)+'&message='+encodeURIComponent(data.message);return true;
    }

    if(row.improvement_id){
      const {data:proposal,error}=await sb.from('improvement_proposals').select('id').eq('id',row.improvement_id).maybeSingle();
      if(error||!proposal){onError('المقترح غير متاح لك حاليًا.');return false;}
      if(!await markRead())return false;
      location.href=depthPrefix+'workspace/improvements.html?id='+encodeURIComponent(proposal.id);return true;
    }
    if(row.project_id){
      const {data:project,error}=await sb.from('projects').select('id').eq('id',row.project_id).maybeSingle();
      if(error||!project){onError('المشروع غير متاح لك حاليًا.');return false}
      if(!await markRead())return false;
      location.href=`${depthPrefix}projects/index.html?id=${encodeURIComponent(project.id)}&view=chat`;return true;
    }
    if(row.task_id){
      const {data:task,error}=await sb.from('tasks').select('id,assignee_id,status,deleted_at,legacy_metadata').eq('id',row.task_id).maybeSingle();
      if(error||!task||task.deleted_at){onError('تعذر العثور على المهمة المرتبطة بهذا الإشعار.');return false}
      const workflow=task.legacy_metadata?.job_workflow;
      if(workflow){
        let route='';
        if(workflow.policy_id)route='policies/index.html?id='+encodeURIComponent(workflow.policy_id)+'&version='+encodeURIComponent(workflow.policy_version_id||'');
        else if(workflow.request_id)route='job-library/employee-changes.html?id='+encodeURIComponent(workflow.request_id);
        else if(workflow.phase==='EMPLOYEE_ACK'){
          const {data:{session}}=await sb.auth.getSession();if(session?.user?.id===task.assignee_id)route='profile/index.html?view=job';
        }else if(workflow.job_id)route='job-library/review.html?id='+encodeURIComponent(workflow.job_id);
        if(route){if(!await markRead())return false;location.href=depthPrefix+route;return true;}
      }
      if(!await markRead())return false;
      const scope=task.status==='مكتملة'?'&scope=COMPLETED':'';
      location.href=`${depthPrefix}tasks/index.html?task=${encodeURIComponent(task.id)}&owner=${encodeURIComponent(task.assignee_id||'')}&notification=${encodeURIComponent(row.id)}${scope}`;
      return true;
    }
    if(!await markRead())return false;
    location.href=row.type==='overdue_summary'?`${depthPrefix}tasks/index.html?scope=OVERDUE`:row.type==='JOB_DESCRIPTION_ASSIGNED'?`${depthPrefix}profile/index.html?view=job#job-profile`:`${depthPrefix}home.html`;
    return true;
  };

  const notificationLabels={tasks:'المهام',communication:'التواصل',projects:'المشاريع',fleet:'الأسطول',recruitment:'التوظيف',it_support:'دعم تقنية المعلومات',workspace:'مساحتي',employees:'الموظفون',job_library:'مكتبة الوظائف',policies:'السياسات',profile:'ملفي الوظيفي',home:'النظام'};
  let notificationSnapshot=null;
  const notificationEsc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  function paintModuleBadges(data=notificationSnapshot){
    for(const link of document.querySelectorAll('.atwar-nav a[href]')){
      const path=new URL(link.href,location.href).pathname;
      const module=link.dataset.notificationModule||window.AtwarModules?.routeModule?.(path)||(/\/profile\//.test(path)?'profile':/\/home\.html$/.test(path)?'home':'');
      if(!module)continue;
      let badge=link.querySelector('.atwar-module-badge');
      const count=Number(data?.modules?.[module])||0;
      if(!badge&&count){badge=document.createElement('span');badge.className='atwar-module-badge';badge.setAttribute('aria-hidden','true');link.append(badge);}
      if(badge){const text=count>99?'99+':String(count);if(badge.textContent!==text)badge.textContent=text;badge.hidden=!count;}
      const label=link.dataset.notificationLabel||(link.dataset.notificationLabel=link.querySelector('span:not(.atwar-module-badge)')?.textContent||link.textContent);
      link.setAttribute('aria-label',label+(count?`، ${count} إشعارًا غير مقروء`:''));
    }
  }
  window.atwarNotifyReadChange=()=>{
    window.dispatchEvent(new Event('atwar:notifications-changed'));
    try{localStorage.setItem('atwar-notification-change',String(Date.now())+Math.random())}catch{}
  };
  window.AtwarNotifications={get snapshot(){return notificationSnapshot},refresh:async()=>null};
  window.atwarInitGlobalNotifications=async function(headerEl,depthPrefix=''){
    if(!headerEl||headerEl.dataset.notificationsReady==='1')return;
    const button=headerEl.querySelector('[data-global-notification-button]'),panel=headerEl.querySelector('[data-global-notification-panel]'),list=headerEl.querySelector('[data-global-notification-list]'),badge=headerEl.querySelector('[data-global-notification-badge]'),markAll=headerEl.querySelector('[data-global-mark-read]');
    if(!button||!panel||!list||!badge)return;
    headerEl.dataset.notificationsReady='1';let pending=null,actor=null,rows=[],sb,timer,stopped=false,realtime,refreshAgain=false;
    button.setAttribute('aria-expanded','false');button.setAttribute('aria-label','الإشعارات');
    const close=()=>{panel.classList.add('hidden');button.setAttribute('aria-expanded','false')};
    button.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();const opening=panel.classList.contains('hidden');panel.classList.toggle('hidden',!opening);button.setAttribute('aria-expanded',String(opening));if(opening){list.innerHTML='<p class="atwar-notification-state">تحديث الإشعارات…</p>';void refresh()}});
    panel.addEventListener('click',e=>e.stopPropagation());document.addEventListener('click',close);
    headerEl.addEventListener('keydown',e=>{if(e.key==='Escape'&&!panel.classList.contains('hidden')){close();button.focus()}});
    const ago=ts=>{const m=Math.max(0,Math.floor((Date.now()-new Date(ts).getTime())/60000));return m<1?'الآن':m<60?`منذ ${m} د`:m<1440?`منذ ${Math.floor(m/60)} س`:`منذ ${Math.floor(m/1440)} يوم`};
    function render(data){
      notificationSnapshot=data;rows=data.items;paintModuleBadges(data);
      const count=Number(data.total_unread)||0;badge.textContent=count>99?'99+':String(count);badge.classList.toggle('hidden',count===0);button.setAttribute('aria-label',count?`الإشعارات، ${count} غير مقروء`:'الإشعارات');
      list.innerHTML=rows.length?rows.slice(0,30).map(n=>`<button type="button" data-global-notification-id="${notificationEsc(n.id)}" class="atwar-global-notification-item ${n.read_at?'':'is-unread'}"><span class="atwar-global-notification-icon" aria-hidden="true">${n.read_at?'✓':'●'}</span><span class="atwar-global-notification-copy"><span class="atwar-notification-module">${notificationEsc(notificationLabels[n.module]||'النظام')}</span><b>${notificationEsc(n.title||'إشعار')}</b><small>${notificationEsc(n.message||n.detail||'')}</small>${n.unread_count>1?`<small>${Number(n.unread_count)} تحديثات جديدة على الطلب نفسه</small>`:''}</span><span class="atwar-global-notification-time">${ago(n.created_at)}</span></button>`).join(''):'<p class="atwar-notification-state">لا توجد إشعارات.</p>';
      list.querySelectorAll('[data-global-notification-id]').forEach(control=>control.onclick=async()=>{const row=rows.find(n=>String(n.id)===control.dataset.globalNotificationId);if(!row)return;control.disabled=true;const opened=await window.atwarOpenNotificationRecord(sb,row,depthPrefix,message=>window.AtwarUI?.toast(message,'error'));control.disabled=false;if(opened)close();else await refresh()});
      window.dispatchEvent(new CustomEvent('atwar:notifications',{detail:data}));
    }
    async function announce(data,user){
      // Communication already has server-claimed alerts, sound and optional desktop delivery.
      const key='atwar-notification-seen-'+user;
      const claim=()=>{let previous;try{previous=localStorage.getItem(key)}catch{}const newest=data.items.reduce((n,row)=>Math.max(n,new Date(row.created_at).getTime()||0),0);try{localStorage.setItem(key,String(Math.max(Number(previous)||0,newest)))}catch{}return previous===null||previous===undefined?[]:data.items.filter(n=>!n.read_at&&n.module!=='communication'&&new Date(n.created_at).getTime()>Number(previous));};
      const fresh=navigator.locks?await navigator.locks.request(key,claim):claim();
      if(!fresh.length||document.visibilityState!=='visible')return;
      const row=fresh[0];button.classList.add('has-new-notification');setTimeout(()=>button.classList.remove('has-new-notification'),2500);
      document.querySelector('[data-atwar-arrival]')?.remove();
      const toast=document.createElement('section');toast.className='atwar-notification-arrival';toast.dataset.atwarArrival='1';toast.setAttribute('role','status');
      const copy=document.createElement('div'),title=document.createElement('b'),text=document.createElement('span');title.textContent=fresh.length>1?`لديك ${fresh.length} مستجدات جديدة`:notificationLabels[row.module]||'إشعار جديد';text.textContent=row.title||'وصل إشعار جديد';copy.append(title,text);
      const open=document.createElement('button');open.type='button';open.textContent='فتح';open.onclick=()=>{if(fresh.length>1){toast.remove();if(panel.classList.contains('hidden'))button.click();}else void window.atwarOpenNotificationRecord(sb,row,depthPrefix,message=>window.AtwarUI?.toast(message,'error'))};
      const dismiss=document.createElement('button');dismiss.type='button';dismiss.textContent='×';dismiss.setAttribute('aria-label','إغلاق التنبيه');dismiss.onclick=()=>toast.remove();toast.append(copy,open,dismiss);document.body.append(toast);setTimeout(()=>toast.remove(),9000);
      if(window.atwarNotificationSound.enabled()&&soundTypes[row.type])window.atwarNotificationSound.play(soundTypes[row.type]);
    }
    async function refresh(force=false){
      if(stopped)return;if(pending){if(force===true)refreshAgain=true;return pending;}
      pending=(async()=>{try{
        sb=await window.atwarGetSupabase();const {data:{session},error:authError}=await sb.auth.getSession();if(authError)throw authError;
        if(!session?.user){actor=null;render({total_unread:0,modules:{},items:[]});return;}
        const user=session.user.id;actor=user;window.atwarStartPresence(sb);
        const {data,error}=await sb.rpc('notification_overview',{p_limit:100});if(error)throw error;
        if(stopped||actor!==user)return;
        if(!data||!Array.isArray(data.items)||!data.modules)throw Error('Invalid notification response');
        render(data);await announce(data,user);
        if(!realtime&&sb.channel){realtime=sb.channel('atwar-notifications-'+user).on('postgres_changes',{event:'*',schema:'public',table:'notifications',filter:'recipient_id=eq.'+user},()=>{if(document.visibilityState==='visible')void refresh(true)}).subscribe();}
      }catch(error){console.error('Global notifications:',error);list.innerHTML='<p class="atwar-notification-state" role="status">تعذر تحديث الإشعارات. <button type="button" data-notification-retry>إعادة المحاولة</button></p>';list.querySelector('[data-notification-retry]').onclick=()=>void refresh();}finally{pending=null;if(refreshAgain){refreshAgain=false;queueMicrotask(()=>void refresh())}}})();return pending;
    }
    window.AtwarNotifications.refresh=async()=>{await refresh(true);while(pending)await pending;return notificationSnapshot};headerEl._atwarRefreshNotifications=refresh;
    if(markAll)markAll.onclick=async()=>{if(!notificationSnapshot?.total_unread)return;const approved=await window.AtwarUI.confirm({title:'تحديد الكل كمقروء',message:'سيتم تحديد إشعاراتك الحالية كمقروءة مع الاحتفاظ بها في السجل.',confirmText:'تحديد كمقروء'});if(!approved)return;const cutoff=new Date().toISOString();const {error}=await sb.from('notifications').update({read_at:cutoff}).is('read_at',null).lte('created_at',cutoff);if(error)window.AtwarUI.toast('تعذر تحديث الإشعارات.','error');else window.atwarNotifyReadChange()};
    const startRefreshTimer=()=>{clearInterval(timer);timer=setInterval(()=>{if(document.visibilityState==='visible')void refresh()},30000)};
    const stopRefreshTimer=event=>{clearInterval(timer);if(event.persisted)window.addEventListener('pageshow',()=>{startRefreshTimer();void refresh();window.addEventListener('pagehide',stopRefreshTimer,{once:true})},{once:true})};
    window.addEventListener('atwar:notifications-changed',()=>void refresh(true));window.addEventListener('storage',e=>{if(e.key==='atwar-notification-change')void refresh(true)});document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')void refresh()});window.addEventListener('online',()=>void refresh());
    const observer=new MutationObserver(records=>{if(records.some(r=>[...r.addedNodes].some(n=>n.nodeType===1&&(n.matches('a[href],atwar-sidebar')||n.querySelector?.('.atwar-nav')))))paintModuleBadges()});observer.observe(document.body,{subtree:true,childList:true});
    if(typeof window.atwarGetSupabase!=='function')return;
    try{sb=await window.atwarGetSupabase();sb.auth.onAuthStateChange?.((event,session)=>{if(event==='SIGNED_OUT'||actor&&session?.user?.id&&session.user.id!==actor){actor=null;notificationSnapshot=null;rows=[];render({total_unread:0,modules:{},items:[]});close();if(realtime){void sb.removeChannel(realtime);realtime=null;}}});}catch{}
    await refresh();startRefreshTimer();window.addEventListener('pagehide',stopRefreshTimer,{once:true});
  };

  // One heartbeat per document; server decides identity and timestamp.
  let presenceTimer,presencePending=false;
  window.atwarStartPresence=function(sb){
    if(presenceTimer)return;
    const ping=async()=>{if(presencePending||document.visibilityState!=='visible'||!navigator.onLine)return;presencePending=true;try{await sb.rpc('presence_ping')}catch{}finally{presencePending=false}};
    void ping();presenceTimer=setInterval(ping,45000);
    const visible=()=>{if(document.visibilityState==='visible')void ping()};
    document.addEventListener('visibilitychange',visible);
    window.addEventListener('pagehide',()=>{clearInterval(presenceTimer);presenceTimer=null;document.removeEventListener('visibilitychange',visible)},{once:true});
  };

  window.addEventListener('pageshow',async e=>{if(e.persisted&&typeof window.atwarGetSupabase==='function'){try{window.atwarStartPresence(await window.atwarGetSupabase())}catch{}}});

  window.atwarSyncShellIdentity=function(profile,authUser){
    if(!profile&&!authUser)return;
    const previous=getSession()||{};
    const current={
      uid:profile?.id||profile?.uid||authUser?.id||authUser?.uid||'',
      email:profile?.email||authUser?.email||'',
      name:profile?.full_name||profile?.name||profile?.fullName||authUser?.user_metadata?.full_name||profile?.email||authUser?.email||'المستخدم',
      role:profile?.role||'employee',
      title:profile?.job_title||profile?.title||profile?.jobTitle||profile?.position||previous.title||'',
      managerId:profile?.manager_id||profile?.managerId||previous.managerId||null,
      managerChain:(profile?.managerChain&&typeof profile.managerChain==='object')?profile.managerChain:(previous.managerChain||{}),
      permissions:Array.isArray(profile?.permissions)?profile.permissions:(Array.isArray(previous.permissions)?previous.permissions:[])
    };
    try{localStorage.setItem('atwarSession',JSON.stringify(current))}catch{}
    window.AtwarModules?.apply();
    document.querySelectorAll('[data-user-name]').forEach(x=>x.textContent=current.name);
    document.querySelectorAll('[data-user-title]').forEach(x=>x.textContent=current.title);
    document.querySelectorAll('.atwar-avatar').forEach(x=>x.textContent=(current.name||'م').trim().charAt(0));
  };

  if(!customElements.get('atwar-sidebar'))customElements.define('atwar-sidebar',AtwarSidebar);
  if(!customElements.get('atwar-header'))customElements.define('atwar-header',AtwarHeader);

  document.addEventListener('DOMContentLoaded',()=>{
    document.querySelectorAll('[data-global-search]').forEach(inp=>{
      if(inp.dataset.atwarBound)return;
      inp.dataset.atwarBound='1';
      inp.addEventListener('keydown',e=>{
        if(e.key==='Enter'&&inp.value.trim())location.href=depth()+'search/index.html?q='+encodeURIComponent(inp.value.trim());
      });
    });
    const hs=document.getElementById('taskHeaderSearch');
    if(hs&&!hs.dataset.atwarBound){
      hs.dataset.atwarBound='1';
      hs.addEventListener('input',()=>{
        const main=document.getElementById('searchInput')||[...document.querySelectorAll('input')].find(x=>(x.placeholder||'').includes('بحث في المهام'));
        if(!main)return;
        main.value=hs.value;
        main.dispatchEvent(new Event('input',{bubbles:true}));
        main.dispatchEvent(new Event('change',{bubbles:true}));
      });
    }
    // Maintenance 1.8 hotfix: legacy task details omitted the Pending Approval option.
    // Without this option, a task in that state renders as an apparently blank status row.
    if(/\/tasks\/(?:index\.html)?$/.test(location.pathname)){
      const ensurePendingApprovalStatus=()=>{
        const select=document.getElementById('detailStatus');
        if(!select)return false;
        if(![...select.options].some(o=>o.value==='بانتظار الاعتماد')){
          const completed=[...select.options].find(o=>o.value==='مكتملة');
          const option=document.createElement('option');
          option.value='بانتظار الاعتماد';
          option.textContent='بانتظار الاعتماد';
          completed?select.insertBefore(option,completed):select.appendChild(option);
        }
        return true;
      };
      if(!ensurePendingApprovalStatus()){
        const statusObserver=new MutationObserver(()=>{
          if(ensurePendingApprovalStatus())statusObserver.disconnect();
        });
        statusObserver.observe(document.documentElement,{childList:true,subtree:true});
      }
    }

    if(/\/tasks\/(?:index\.html)?$/.test(location.pathname)){
      const el=document.getElementById('stat-completed');
      const card=el?.closest('div.bg-white')||el?.parentElement;
      if(card){
        card.style.cursor='pointer';
        card.title='فتح المهام المكتملة';
        card.addEventListener('click',()=>{location.href=depth()+'tasks/index.html?scope=COMPLETED'});
      }
    }
    window.lucide?.createIcons();
  });
})();
