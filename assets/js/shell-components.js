
(function(){
  function depth(){
    const nestedModules=['tasks','completed','team','profile','workspace','follow-up','notifications','search','admin','approvals','organization','my-day','recurring'];
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
          ${nav('profile','profile/index.html','circle-user-round','ملفي الوظيفي')}
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
      const d=depth(),mode=this.getAttribute('mode')||'default',s=getSession();
      const currentPath=location.pathname;
      const taskNavActive=key=>{
        if(key==='tasks')return /\/tasks\//.test(currentPath);
        if(key==='completed')return /\/completed\//.test(currentPath);
        if(key==='recurring')return /\/recurring\//.test(currentPath);
        return false;
      };
      const recurringAllowed=!s || ['manager','admin'].includes(s.role);
      const taskModuleOpen=/\/(tasks|completed|recurring)\//.test(currentPath);
      const taskNav=taskModuleOpen?`
        <nav class="atwar-header-task-nav" aria-label="قائمة المهام">
          <a class="${taskNavActive('tasks')?'active':''}" href="${d}tasks/index.html"><i data-lucide="square-check-big"></i><span>النشطة</span></a>
          <a class="${taskNavActive('completed')?'active':''}" href="${d}completed/index.html"><i data-lucide="archive-check"></i><span>المكتملة</span></a>
          ${recurringAllowed?`<a class="${taskNavActive('recurring')?'active':''}" href="${d}recurring/index.html"><i data-lucide="repeat-2"></i><span>الدورية</span></a>`:''}
        </nav>`:'';
      const taskTools=mode==='tasks'?`
        <button type="button" id="addTaskButton" onclick="showQuickAdd()" class="atwar-task-add"><i data-lucide="plus"></i><span>إضافة مهمة</span></button>
        <div class="atwar-task-notification-wrap">
          <button id="notificationButton" type="button" onclick="toggleNotifications()" class="atwar-icon-btn" title="الإشعارات">
            <i data-lucide="bell"></i><span id="notificationBadge" class="hidden atwar-notification-badge">0</span>
          </button>
          <div id="notificationPanel" class="hidden atwar-task-notification-panel">
            <div class="atwar-notification-head"><b>الإشعارات</b><button onclick="markAllNotificationsRead()">تحديد الكل كمقروء</button></div>
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
            <div class="atwar-notification-head"><b>الإشعارات</b><button type="button" data-global-mark-read>تحديد الكل كمقروء</button></div>
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
        @media(max-width:1050px){
          .atwar-header-task-nav{overflow-x:auto;justify-content:flex-start}
          .atwar-header-task-nav a{flex:0 0 auto}
        }
        @media(max-width:600px){.atwar-header-task-nav span{font-size:10px}.atwar-header-task-nav a{padding:7px 8px}}
      </style>
      <header class="atwar-topbar ${mode==='tasks'?'atwar-task-header':''}">
        ${mode==='tasks'?'':`<div class="atwar-top-brand">
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
          <div class="atwar-user">
            <div><div class="atwar-user-name" data-user-name>المستخدم</div><div class="atwar-user-role" data-user-title></div></div>
            <div class="atwar-avatar">أ</div>
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
      if(mode!=='tasks')setTimeout(()=>window.atwarInitGlobalNotifications?.(this,d),0);
    }
  }



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
          if(row?.task_id){
            location.href=`${depthPrefix}tasks/index.html?task=${encodeURIComponent(row.task_id)}&notification=${encodeURIComponent(row.id)}`;
          }else{
            await sb.from('notifications').delete().eq('id',row.id);
            await refresh();
          }
        }));
        markAll.onclick=async()=>{if(!rows.length)return;const ids=rows.map(x=>x.id);const {error:e}=await sb.from('notifications').delete().in('id',ids);if(!e)await refresh();};
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

    // Completed tasks counter remains useful on the active Tasks page,
    // but the completed records themselves are no longer loaded into that page.
    if(/\/tasks\/(?:index\.html)?$/.test(location.pathname)){
      (async()=>{
        try{
          const sb=await window.atwarGetSupabase();
          const {count,error}=await sb.from('tasks')
            .select('id',{count:'exact',head:true})
            .eq('status','مكتملة')
            .is('deleted_at',null);
          if(error)throw error;
          const el=document.getElementById('stat-completed');
          if(el){
            const archiveCount=String(count||0);
            const keepArchiveCount=()=>{if(el.textContent!==archiveCount)el.textContent=archiveCount};
            keepArchiveCount();
            const observer=new MutationObserver(keepArchiveCount);
            observer.observe(el,{childList:true,characterData:true,subtree:true});
            const card=el.closest('div.bg-white')||el.parentElement;
            if(card){
              card.style.cursor='pointer';
              card.title='فتح المهام المكتملة';
              card.addEventListener('click',()=>{location.href=depth()+'completed/index.html'});
            }
          }
        }catch(error){console.warn('Completed tasks count:',error)}
      })();
    }
    window.lucide?.createIcons();
  });
})();
