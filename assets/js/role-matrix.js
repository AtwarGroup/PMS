
window.ATWAR_ROLE_MATRIX_DEFAULTS = {
  employee: {home:true,'my-day':true,workspace:true,tasks:true,'follow-up':true,team:false,approvals:false,profile:true,organization:true,notifications:true,search:true,admin:false},
  manager: {home:true,'my-day':true,workspace:true,tasks:true,'follow-up':true,team:true,approvals:true,profile:true,organization:true,notifications:true,search:true,admin:false},
  admin: {home:true,'my-day':true,workspace:true,tasks:true,'follow-up':true,team:true,approvals:true,profile:true,organization:true,notifications:true,search:true,admin:true}
};

window.getAtwarRoleMatrix = function(){
  try{
    return JSON.parse(localStorage.getItem('atwarRoleMatrix')||'null') || window.ATWAR_ROLE_MATRIX_DEFAULTS;
  }catch{
    return window.ATWAR_ROLE_MATRIX_DEFAULTS;
  }
};
