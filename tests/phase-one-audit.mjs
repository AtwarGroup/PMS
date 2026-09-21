import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root=resolve(new URL('..',import.meta.url).pathname);
const read=file=>readFileSync(resolve(root,file),'utf8');
const failures=[];
const requireText=(file,text)=>{
  if(!existsSync(resolve(root,file)))failures.push(`Missing: ${file}`);
  else if(!read(file).includes(text))failures.push(`Missing contract in ${file}: ${text}`);
};

requireText('admin/index.html','maintenance.html');
requireText('admin/maintenance.html',"sb.rpc('list_deleted_tasks')");
requireText('admin/maintenance.html',"sb.rpc('restore_task_safe'");
requireText('admin/maintenance.html',"email_notification_outbox");
requireText('admin/maintenance.html',"app_error_logs");
requireText('admin/maintenance.html',"admin_audit_log");
requireText('assets/js/supabase-runtime.js',"unhandledrejection");
requireText('assets/js/supabase-runtime.js',"window.atwarReportError");
requireText('supabase/migrations/20260912_phase_one_observability_governance.sql','alter table public.app_error_logs enable row level security');
requireText('supabase/migrations/20260912_phase_one_observability_governance.sql','email_notification_outbox_admin_retry');

const modules=JSON.parse(read('modules.json'));
for(const module of modules.modules||[]){
  if(!existsSync(resolve(root,module.path)))failures.push(`Module path missing: ${module.id} -> ${module.path}`);
}
if(!modules.modules?.some(x=>x.id==='maintenance'&&x.minRole==='admin'))failures.push('Maintenance module must be admin-only.');

if(failures.length){console.error(failures.join('\n'));process.exit(1)}
console.log('Phase-one observability and governance audit passed.');
