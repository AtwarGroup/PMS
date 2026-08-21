
window.ATWAR_DEMO_ACCOUNTS = {
  'employee@atwar.local': {
    password: '123456',
    role: 'employee',
    name: 'محمد باسنبل',
    title: 'موظف',
    permissions: ['home','tasks','profile']
  },
  'manager@atwar.local': {
    password: '123456',
    role: 'manager',
    name: 'أكرم يوسف',
    title: 'رئيس الحسابات',
    permissions: ['home','tasks','team','profile','approvals']
  },
  'admin@atwar.local': {
    password: '123456',
    role: 'admin',
    name: 'مدير النظام',
    title: 'مدير النظام',
    permissions: ['home','tasks','team','profile','approvals','settings','users']
  }
};

window.ATWAR_ROLE_RANK = {
  employee: 1,
  manager: 2,
  admin: 3
};
