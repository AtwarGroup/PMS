
(function(){
  function depth(){
    const parts=location.pathname.split('/').filter(Boolean);
    const pms=parts.lastIndexOf('PMS');
    const after=pms>=0?parts.slice(pms+1):parts;
    return after.length>1?'../':'';
  }
  function getSession(){
    try{return JSON.parse(localStorage.getItem('atwarSession')||'null')}catch{return null}
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
          ${nav('home','home.html','home','الرئيسية')}
          ${nav('tasks','tasks/index.html','square-check-big','المهام')}
          ${nav('notes','workspace/index.html','notebook-tabs','مساحة عملي')}
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
    const ago=ts=>{const d=Math.max(0,Date.now()-Number(ts||0)),m=Math.floor(d/60000);if(m<1)return'الآن';if(m<60)return`منذ ${m} د`;const h=Math.floor(m/60);return h<24?`منذ ${h} س`:`منذ ${Math.floor(h/24)} يوم`};

    try{
      let tries=0;while(!window.ATWAR_FIREBASE_CONFIG&&tries<20){await new Promise(r=>setTimeout(r,100));tries++}
      if(!window.ATWAR_FIREBASE_CONFIG)throw new Error('Firebase config unavailable');

      const appMod=await import('https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js');
      const authMod=await import('https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js');
      const dbMod=await import('https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js');
      const app=appMod.getApps().length?appMod.getApps()[0]:appMod.initializeApp(window.ATWAR_FIREBASE_CONFIG);
      const auth=authMod.getAuth(app),db=dbMod.getDatabase(app);

      authMod.onAuthStateChanged(auth,user=>{
        if(!user)return;
        const q=dbMod.query(dbMod.ref(db,`notificationsByUser/${user.uid}`),dbMod.orderByChild('createdAt'),dbMod.limitToLast(30));
        dbMod.onValue(q,snap=>{
          let rows=snap.exists()?Object.entries(snap.val()).map(([id,v])=>({id,...v})).sort((a,b)=>Number(b.createdAt||0)-Number(a.createdAt||0)):[];
          // تنظيف تنبيهات التأخير القديمة الخاصة بمهام الفريق بعد اعتماد التنبيه الملخص.
          const legacyTeamOverdue=rows.filter(x=>x.type==='overdue'&&x.ownerUid&&String(x.ownerUid)!==String(user.uid));
          if(legacyTeamOverdue.length){
            rows=rows.filter(x=>!legacyTeamOverdue.some(old=>old.id===x.id));
          }
          const unread=rows.filter(x=>!x.read).length;
          badge.textContent=unread>99?'99+':String(unread);badge.classList.toggle('hidden',unread===0);
          list.innerHTML=rows.length?rows.slice(0,8).map(n=>`
            <button type="button" data-global-notification-id="${esc(n.id)}" data-owner-uid="${esc(n.ownerUid||'')}" class="atwar-global-notification-item ${n.read?'':'is-unread'}">
              <span class="atwar-global-notification-icon">${(n.type==='overdue'||n.type==='overdue_summary')?'⚠️':n.type==='approved'?'✅':n.type==='approval'?'⏳':n.type==='manager_note'?'📝':'🔔'}</span>
              <span class="atwar-global-notification-copy"><b>${esc(n.title||'إشعار')}</b><small>${esc(n.message||'')}</small></span>
              <span class="atwar-global-notification-time">${ago(n.createdAt)}</span>
            </button>`).join(''):'<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">لا توجد إشعارات جديدة.</div>';

          list.querySelectorAll('[data-global-notification-id]').forEach(btn=>btn.addEventListener('click',async()=>{
            const id=btn.dataset.globalNotificationId,ownerUid=btn.dataset.ownerUid||'';
            const row=rows.find(x=>x.id===id);
            try{await dbMod.update(dbMod.ref(db,`notificationsByUser/${user.uid}/${id}`),{read:true})}catch{}
            panel.classList.add('hidden');
            if(row?.type==='overdue_summary'){
              location.href=`${depthPrefix}tasks/index.html?scope=OVERDUE`;
            }else if(ownerUid&&row?.taskKey){
              location.href=`${depthPrefix}tasks/index.html?owner=${encodeURIComponent(ownerUid)}&task=${encodeURIComponent(row.taskKey)}`;
            }else if(ownerUid){
              location.href=`${depthPrefix}tasks/index.html?owner=${encodeURIComponent(ownerUid)}`;
            }
          }));
          markAll.onclick=async()=>{const changes={};rows.filter(x=>!x.read).forEach(x=>changes[`${x.id}/read`]=true);if(Object.keys(changes).length){try{await dbMod.update(dbMod.ref(db,`notificationsByUser/${user.uid}`),changes)}catch{}}};
        },()=>{list.innerHTML='<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">الإشعارات غير متاحة حالياً.</div>'});
      });
    }catch(error){
      console.error('Global notifications:',error);
      list.innerHTML='<div style="padding:26px;text-align:center;font-size:10px;color:#94a3b8">الإشعارات غير متاحة حالياً.</div>';
    }
  };

  window.atwarSyncShellIdentity=function(profile,authUser){
    if(!profile&&!authUser)return;
    const current={
      uid:profile?.uid||authUser?.uid||'',
      email:profile?.email||authUser?.email||'',
      name:profile?.name||profile?.fullName||authUser?.displayName||profile?.email||authUser?.email||'المستخدم',
      role:profile?.role||'employee',
      title:profile?.title||profile?.jobTitle||profile?.position||''
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
    window.lucide?.createIcons();
  });
})();
