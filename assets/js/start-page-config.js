window.ATWAR_START_PAGE = {
  employee: 'home.html',
  manager: 'home.html',
  admin: 'home.html'
};

window.ATWAR_START_LABEL = {
  employee: 'الرئيسية',
  manager: 'الرئيسية',
  admin: 'الرئيسية'
};

window.atwarModuleStart=function(role){const c=window.AtwarModules?.context;if(!c||role==='admin')return 'home.html';const units=c.catalog.filter(m=>m.ready&&c.allowed.includes(m.key)&&m.key!=='policies');const all=c.catalog.filter(m=>m.ready&&c.allowed.includes(m.key));return units.length===1?units[0].path:all.length===1?all[0].path:'home.html';};
