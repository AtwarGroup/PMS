
document.addEventListener('DOMContentLoaded',()=>{
  const session=(typeof getAtwarDemoSession==='function')?getAtwarDemoSession():null;

  // Remove deprecated modules from persistent navigation.
  const removeLabels=['يومي','مساحة عملي','الاعتمادات','الهيكل التنظيمي','ابدأ من صفحتي'];
  document.querySelectorAll('.atwar-nav a, .atwar-side-link').forEach(el=>{
    if(removeLabels.includes((el.textContent||'').trim())) el.style.display='none';
  });

  // Employees do not see Team.
  if(session?.role==='employee'){
    document.querySelectorAll('.atwar-nav a').forEach(el=>{
      if((el.textContent||'').trim()==='الفريق') el.style.display='none';
    });
  }
});
