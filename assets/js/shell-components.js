
(function(){
  const shellScript=document.currentScript;
  const assetRoot=new URL('../',shellScript?.src||location.href);
  if(!document.querySelector('link[data-atwar-design-system]')){
    const style=document.createElement('link');style.rel='stylesheet';style.dataset.atwarDesignSystem='1';style.href=new URL('css/design-system.css?v=2.5.0',assetRoot).href;document.head.append(style);
  }
  if(!window.AtwarUI&&!document.querySelector('script[data-atwar-ui-feedback]')){
    const ui=document.createElement('script');ui.dataset.atwarUiFeedback='1';ui.src=new URL('js/ui-feedback.js?v=2.5.0',assetRoot).href;document.head.append(ui);
  }
  if(!window.AtwarSession&&!document.querySelector('script[data-atwar-session-service]')){
    const session=document.createElement('script');session.dataset.atwarSessionService='1';session.src=new URL('js/session-service.js?v=2.5.0',assetRoot).href;document.head.append(session);
  }
  if(!document.querySelector('link[rel~="icon"]')){
    const icon=document.createElement('link');icon.rel='icon';icon.type='image/svg+xml';
    icon.href=new URL('../../favicon.svg',document.currentScript?.src||location.href).href;
    document.head.append(icon);
  }
  function depth(){
    const nestedModules=['tasks','completed','team','profile','workspace','follow-up','notifications','search','admin','approvals','organization','job-library','my-day','recurring'];
    return nestedModules.some(name=>location.pathname.includes('/'+name+'/'))?'../':'';
  }
  function getSession(){
    try{return JSON.parse(localStorage.getItem('atwarSession')||'null')}catch{return null}
  }
  const rank={employee:1,manager:2,admin:3};

  class AtwarSidebar extends HTMLElement{
    connectedCallback(){
      const d=depth(),requestedActive=this.getAttribute('active')||'',s=getSession();
      const inTaskModule=/\/(tasks|completed|recurring)\//.test(location.pathname);
      const active=inTaskModule?'tasks':requestedActive;
      const nav=(key,path,icon,label,min='employee')=>{
        if(s && (rank[s.role]||0)<(rank[min]||0))return '';
        return `<a class="${active===key?'active':''}" href="${d}${path}">
          <i data-lucide="${icon}"></i><span>${label}</span></a>`;
      };
      this.innerHTML=`<aside class="atwar-sidebar">
        <div class="atwar-brand"><h1>ATWAR ONE</h1><p>نظام إدارة الأداء المؤسسي</p></div>
        <nav class="atwar-nav">
          ${nav('home','home.html','home','الرئيسية')}
          ${nav('tasks','tasks/index.html','square-check-big','المهام')}
          ${nav('notes','workspace/index.html','notebook-tabs','مساحة عملي')}
          ${nav('team','team/index.html','users','الفريق','manager')}
          ${nav('jobLibrary','job-library/index.html','library-big','مكتبة الوظائف','manager')}
          ${nav('profile','profile/index.html','circle-user-round','الملف التعريفي')}
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
      const d=depth(),mode=this.getAttribute('mode')||'default',s=getSession(),taskSuiteMode=mode==='tasks'||mode==='task-suite'||currentPath.endsWith('/tasks/executive.html');
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
      const taskNav=taskModuleOpen?`
        <nav class="atwar-header-task-nav" aria-label="قائمة المهام">
          <a class="${taskNavActive('tasks')?'active':''}" href="${d}tasks/index.html"><i data-lucide="square-check-big"></i><span>النشطة</span></a>
          <a class="${taskNavActive('completed')?'active':''}" href="${d}tasks/index.html?scope=COMPLETED"><i data-lucide="archive-check"></i><span>المكتملة</span></a>
          ${recurringAllowed?`<a class="${taskNavActive('recurring')?'active':''}" href="${d}recurring/index.html"><i data-lucide="repeat-2"></i><span>الدورية</span></a>`:''}
          ${executiveAllowed?`<a class="${taskNavActive('executive')?'active':''}" href="${d}tasks/executive.html"><i data-lucide="scan-eye"></i><span>الاطلاع التنفيذي</span></a>`:''}
        </nav>`:'';
      const taskTools=mode==='tasks'?`
        <button type="button" id="addTaskButton" onclick="showQuickAdd()" class="atwar-task-add"><i data-lucide="plus"></i><span>إضافة مهمة</span></button>
        <div class="atwar-task-notification-wrap">
          <button id="notificationButton" type="button" onclick="toggleNotifications()" class="atwar-icon-btn" title="الإشعارات">
            <i data-lucide="bell"></i><span id="notificationBadge" class="hidden atwar-notification-badge">0</span>
          </button>
          <div id="notificationPanel" class="hidden atwar-task-notification-panel">
            <div class="atwar-notification-head"><b>الإشعارات</b><button onclick="markAllNotificationsRead()">مسح جميع الإشعارات</button></div>
            <div id="notificationList" class="atwar-notification-list"></div>
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
            <div class="atwar-notification-head"><b>الإشعارات</b><button type="button" data-global-mark-read>مسح جميع الإشعارات</button></div>
            <div class="atwar-notification-list" data-global-notification-list><div style="padding:24px;text-align:center;font-size:10px;color:#94a3b8">جاري تحميل الإشعارات...</div></div>
            <a href="${d}notifications/index.html" style="display:block;padding:10px 14px;text-align:center;font-size:10px;font-weight:900;color:#2563eb;text-decoration:none;border-top:1px solid #eef2f7">عرض جميع الإشعارات</a>
          </div>
        </div>`;

      this.innerHTML=`<style>
        .atwar-topbar{flex-wrap:nowrap}
        .atwar-header-task-nav{display:flex;align-items:center;gap:4px;padding:4px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.10);border-radius:12px;white-space:nowrap}
        .atwar-header-task-nav a{display:flex;align-items:center;gap:6px;text-decoration:none;color:#dbeafe;font-size:11px;font-weight:800;padding:8px 10px;border-radius:9px;transition:.15s ease}
        .atwar-header-task-nav a:hover{background:rgba(255,255,255,.09);color:#fff}
        .atwar-header-task-nav a.active{background:#2684ff;color:#fff}
        .atwar-header-task-nav svg{width:15px;height:15px}
        .atwar-account-wrap{position:relative;flex:0 0 auto}
        .atwar-account-trigger{border:0;background:transparent;color:inherit;cursor:pointer;padding:4px 6px!important;min-height:44px!important;border-radius:12px!important}
        .atwar-account-trigger:hover,.atwar-account-trigger[aria-expanded="true"]{background:rgba(255,255,255,.08)}
        .atwar-account-menu{position:absolute;left:0;top:calc(100% + 10px);width:280px;background:#fff;color:#24364b;border:1px solid #dfe7f0;border-radius:16px;box-shadow:0 22px 55px rgba(15,23,42,.22);overflow:hidden;z-index:1300;text-align:right}
        .atwar-account-summary{display:flex;align-items:center;gap:11px;padding:15px;border-bottom:1px solid #edf2f7;background:#f8fafc}
        .atwar-account-summary .atwar-avatar{background:#e8f2ff!important;color:#1769e0!important}
        .atwar-account-copy{min-width:0}.atwar-account-copy b,.atwar-account-copy span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.atwar-account-copy b{font-size:12px}.atwar-account-copy span{font-size:10px;color:#64748b;margin-top:3px}
        .atwar-account-links{padding:7px}.atwar-account-links a,.atwar-account-links button{width:100%;min-height:40px!important;display:flex;align-items:center;gap:10px;padding:9px 11px!important;border:0;background:transparent;color:#334155;text-decoration:none;font-size:11px!important;font-weight:800;text-align:right;cursor:pointer;border-radius:9px!important}
        .atwar-account-links a:hover,.atwar-account-links button:hover{background:#f1f5f9}.atwar-account-links svg{width:16px;height:16px;color:#64748b}.atwar-account-links .danger{color:#dc2626;border-top:1px solid #edf2f7;margin-top:5px;border-radius:0!important}.atwar-account-links .danger svg{color:#dc2626}
        @media(max-width:1050px){
          .atwar-header-task-nav{overflow-x:auto;justify-content:flex-start}
          .atwar-header-task-nav a{flex:0 0 auto}
        }
        @media(max-width:600px){.atwar-header-task-nav span{font-size:10px}.atwar-header-task-nav a{padding:7px 8px}}
      </style>
      <header class="atwar-topbar ${mode==='tasks'?'atwar-task-header':''}">
        ${taskSuiteMode?'':`<div class="atwar-top-brand">
          <div class="atwar-brand-mark"></div>
          <div class="atwar-org-title">
              <h2>نظام إدارة الأداء المؤسسي</h2>
              <p>مؤسسة أطوار للتجارة</p>
            </div>
          <div class="atwar-pm-label">Performance Management<br>System</div>
        </div>`}
        ${mode==='tasks'?`<span id="pageSubtitle" class="hidden"></span>`:''}
        ${taskNav}
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
                <a href="${d}profile/index.html" role="menuitem"><i data-lucide="circle-user-round"></i><span>الملف التعريفي</span></a>
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
      if(mode!=='tasks')setTimeout(()=>window.atwarInitGlobalNotifications?.(this,d),0);
    }
  }



  window.atwarOpenNotificationRecord=async function(sb,row,depthPrefix='',onError=()=>{}){
    if(!row)return false;
    if(row.task_id){
      const {data:task,error}=await sb.from('tasks').select('id,assignee_id,status,deleted_at').eq('id',row.task_id).maybeSingle();
      if(error||!task||task.deleted_at){onError('تعذر العثور على المهمة المرتبطة بهذا الإشعار.');return false}
      const scope=task.status==='مكتملة'?'&scope=COMPLETED':'';
      location.href=`${depthPrefix}tasks/index.html?task=${encodeURIComponent(task.id)}&owner=${encodeURIComponent(task.assignee_id||'')}&notification=${encodeURIComponent(row.id)}${scope}`;
      return true;
    }
    const {error}=await sb.from('notifications').delete().eq('id',row.id);
    if(error){onError('تعذر مسح الإشعار الآن.');return false}
    location.href=row.type==='overdue_summary'?`${depthPrefix}tasks/index.html?scope=OVERDUE`:row.type==='JOB_DESCRIPTION_ASSIGNED'?`${depthPrefix}profile/job-description.html`:`${depthPrefix}home.html`;
    return true;
  };

  window.atwarInitGlobalNotifications=async function(headerEl,depthPrefix=''){
    if(!headerEl||headerEl.dataset.notificationsReady==='1')return;
    const button=headerEl.querySelector('[data-global-notification-button]');
    const panel=headerEl.querySelector('[data-global-notification-panel]');
    const list=headerEl.querySelector('[data-global-notification-list]');
    const badge=headerEl.querySelector('[data-global-notification-badge]');
    const markAll=headerEl.querySelector('[data-global-mark-read]');
    if(!button||!panel||!list||!badge)return;
    headerEl.dataset.notificationsReady='1';
    button.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();panel.classList.toggle('hidden')});
    panel.addEventListener('click',e=>e.stopPropagation());
    document.addEventListener('click',()=>panel.classList.add('hidden'));
    const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
    const ago=ts=>{if(!ts)return'';const d=Math.max(0,Date.now()-new Date(ts).getTime()),m=Math.floor(d/60000);if(m<1)return'الآن';if(m<60)return`منذ ${m} د`;const h=Math.floor(m/60);return h<24?`منذ ${h} س`:`منذ ${Math.floor(h/24)} يوم`};
    async function refresh(){
      try{
        const sb=await window.atwarGetSupabase();
        const {data:{session}}=await sb.auth.getSession();
        if(!session?.user){list.innerHTML='<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">سجل الدخول لعرض الإشعارات.</div>';return;}
        const {data,error}=await sb.from('notifications').select('*').order('created_at',{ascending:false}).limit(30);
        if(error)throw error;
        const rows=data||[];
        badge.textContent=rows.length>99?'99+':String(rows.length);badge.classList.toggle('hidden',rows.length===0);
        list.innerHTML=rows.length?rows.slice(0,8).map(n=>`<button type="button" data-global-notification-id="${esc(n.id)}" class="atwar-global-notification-item is-unread"><span class="atwar-global-notification-icon">🔔</span><span class="atwar-global-notification-copy"><b>${esc(n.title||n.type||'إشعار')}</b><small>${esc(n.message||n.detail||'')}</small></span><span class="atwar-global-notification-time">${ago(n.created_at)}</span></button>`).join(''):'<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">لا توجد إشعارات جديدة.</div>';
        list.querySelectorAll('[data-global-notification-id]').forEach(btn=>btn.addEventListener('click',async()=>{
          const row=rows.find(x=>String(x.id)===btn.dataset.globalNotificationId);
          // سياسة ATWAR ONE: فتح الإشعار يحذفه بعد نجاح الوصول للعنصر المرتبط.
          panel.classList.add('hidden');
          const opened=await window.atwarOpenNotificationRecord(sb,row,depthPrefix,()=>{});
          if(!opened)await refresh();
        }));
        markAll.onclick=async()=>{if(!rows.length||!confirm('هل تريد مسح جميع الإشعارات؟'))return;const ids=rows.map(x=>x.id);const {error:e}=await sb.from('notifications').delete().in('id',ids);if(!e)await refresh();};
      }catch(error){console.error('Global notifications:',error);list.innerHTML='<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">الإشعارات غير متاحة حالياً.</div>';}
    }
    await refresh();
    headerEl._atwarRefreshNotifications=refresh;
  };

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
