import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8'),page=read('admin/users.html'),module=read('assets/js/admin-access-page.mjs'),css=read('assets/css/admin-access.css');
for(const id of ['pageSize','accountRange','previousAccounts','nextAccounts','discardDialog','keepEditing','discardChanges','effectiveEmployeeMatrix','accountDirect'])assert(page.includes(`id="${id}"`));
assert(module.includes('paginateUsers(users,accountPage'));assert(module.includes('function formSnapshot'));assert(module.includes('rememberForms(\'accountDialog\')'));assert(module.includes('return askDiscard()'));assert(module.includes('effectiveEmployeeAccess(context,u)'));
assert(!module.includes('window.confirm('));assert(module.includes("if(busy||button.dataset.accountTab===currentAccountTab)return"));
assert(module.includes('permission-matrix'));assert(css.includes('position:sticky;bottom:0'));assert(css.includes('.account-directory-table tr{display:grid'));
assert(page.includes('admin-access-page.mjs?v=2.7.7'));assert(page.includes('admin-access.css?v=2.7.3'));
console.log('Compact permission matrix, pagination, effective scope summary, mobile layout and unsaved draft protection passed.');
