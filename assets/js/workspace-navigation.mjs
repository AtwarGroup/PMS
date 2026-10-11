// View selection changes presentation only; workspace data and permissions stay in their existing modules.
export function initWorkspaceNavigation({doc=document,win=window}={}){
 const tabs=[...doc.querySelectorAll('[data-workspace-tab]')],views=[...doc.querySelectorAll('[data-workspace-view]')];
 let active='Daily';
 function select(key,{writeHash=false,focus=false}={}){
  const tab=tabs.find(t=>t.dataset.workspaceTab===key);if(!tab||tab.hidden)return false;
  active=key;
  for(const t of tabs){const selected=t===tab;t.setAttribute('aria-selected',String(selected));t.tabIndex=selected?0:-1;}
  for(const v of views)v.hidden=v.dataset.workspaceView!==key;
  if(writeHash)win.history.replaceState(null,'','#'+tab.getAttribute('aria-controls'));
  if(focus)tab.focus();return true;
 }
 function followHash(){
  let id;try{id=decodeURIComponent(win.location.hash.slice(1));}catch{return;}
  if(!id)return;
  const target=doc.getElementById(id),view=target?.closest('[data-workspace-view]');
  if(view&&select(view.dataset.workspaceView))target.scrollIntoView?.({block:'start',behavior:'auto'});
 }
 for(const tab of tabs){
  tab.addEventListener('click',()=>select(tab.dataset.workspaceTab,{writeHash:true}));
  tab.addEventListener('keydown',event=>{
   const visible=tabs.filter(t=>!t.hidden),index=visible.indexOf(tab);let next;
   if(event.key==='ArrowLeft')next=visible[(index+1)%visible.length];
   else if(event.key==='ArrowRight')next=visible[(index-1+visible.length)%visible.length];
   else if(event.key==='Home')next=visible[0];else if(event.key==='End')next=visible.at(-1);else return;
   event.preventDefault();select(next.dataset.workspaceTab,{writeHash:true,focus:true});
  });
 }
 doc.getElementById('spaceSummary')?.addEventListener('click',event=>{
  const link=event.target.closest?.('a[href^="#"]');if(!link)return;
  const target=doc.getElementById(link.getAttribute('href').slice(1)),view=target?.closest('[data-workspace-view]');
  if(view&&select(view.dataset.workspaceView)){event.preventDefault();win.history.replaceState(null,'',link.getAttribute('href'));target.scrollIntoView?.({block:'start',behavior:'auto'});}
 });
 win.addEventListener('hashchange',followHash);followHash();
 return {setRole(role){const management=tabs.find(t=>t.dataset.workspaceTab==='Management');if(management)management.hidden=!['admin','manager'].includes(role);if(active==='Management'&&management?.hidden)select('Daily');followHash();}};
}
