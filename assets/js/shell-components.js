
(function(){
  function depth(){
    const parts=location.pathname.split('/').filter(Boolean);
    const pms=parts.lastIndexOf('PMS');
    const after=pms>=0?parts.slice(pms+1):parts;
    return after.length>1?'../':'';
  }
  function getSession(){
    try{return JSON.parse(localStorage.getItem('atwarSession')||localStorage.getItem('atwarDemoSession')||'null')}catch{return null}
  }
  const rank={employee:1,manager:2,admin:3};

  class AtwarSidebar extends HTMLElement{
    connectedCallback(){
      const d=depth(),active=this.getAttribute('active')||'',s=getSession();
      const nav=(key,path,icon,label,min='employee')=>{
        if(s && (rank[s.role]||0)<(rank[min]||0))return '';
        return `<a class="${active===key?'active':''}" href="${d}${path}">
          <i data-lucide="${icon}"></i><span>${label}</span></a>`;
      };
      this.innerHTML=`<aside class="atwar-sidebar">
        <div class="atwar-brand"><h1>ATWAR ONE</h1><p>نظام إدارة الأداء المؤسسي</p></div>
        <nav class="atwar-nav">
          ${nav('home','index.html','home','الرئيسية')}
          ${nav('tasks','tasks/index.html','square-check-big','المهام')}
          ${nav('notes','workspace/index.html','notebook-pen','ملاحظاتي')}
          ${nav('follow','follow-up/index.html','clock-arrow-up','المتابعات')}
          ${nav('team','team/index.html','users','الفريق','manager')}
          ${nav('profile','profile/index.html','circle-user-round','ملفي الوظيفي')}
        </nav>
        <div class="atwar-spacer"></div>
        <div class="atwar-side-section">
          <a class="atwar-side-link" href="${d}landing.html"><i data-lucide="layout-grid"></i><span>بوابة الأنظمة</span></a>
          ${s?.role==='admin'?`<a class="atwar-side-link" href="${d}admin/index.html"><i data-lucide="settings"></i><span>إدارة النظام</span></a>`:''}
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
      const d=depth(),mode=this.getAttribute('mode')||'default';
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
        <button type="button" id="usersButton" onclick="openUsersModal()" class="hidden atwar-icon-btn" title="المستخدمون"><i data-lucide="users"></i></button>
        <input id="importFile" type="file" accept=".xlsx" class="hidden" onchange="handleImport(event)">
      `:`<a href="${d}notifications/index.html" class="atwar-bell"><i data-lucide="bell"></i><span class="atwar-badge">5</span></a>`;

      this.innerHTML=`<header class="atwar-topbar ${mode==='tasks'?'atwar-task-header':''}">
        <div class="atwar-top-brand">
          <div class="atwar-brand-mark"></div>
          <div class="atwar-org-title">
              <h2>نظام إدارة الأداء المؤسسي</h2>
              <p>مؤسسة أطوار للتجارة</p>
              ${mode==='tasks'?`<span id="pageSubtitle" class="hidden"></span>`:''}
            </div>
          <div class="atwar-pm-label">Performance Management<br>System</div>
        </div>
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
      const s=getSession();
      if(s){
        this.querySelectorAll('[data-user-name]').forEach(x=>x.textContent=s.name||s.email||'المستخدم');
        this.querySelectorAll('[data-user-title]').forEach(x=>x.textContent=s.title||'');
        const av=this.querySelector('.atwar-avatar');
        if(av)av.textContent=(s.name||s.email||'م').trim().charAt(0);
      }
      window.lucide?.createIcons();
    }
  }

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
    window.lucide?.createIcons();
  });
})();
