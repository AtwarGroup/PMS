import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { calcDelay } from '../assets/js/tasks-core.mjs';
const db=new PGlite();
const task='10000000-0000-4000-8000-000000000001',other='10000000-0000-4000-8000-000000000002',actor='20000000-0000-4000-8000-000000000001';
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.uid',true),'')::uuid$$;
 create table public.tasks(id uuid primary key,deleted_at timestamptz,project_id uuid,owner_id uuid);
 create table public.task_activity(task_id uuid,event_type text,created_at timestamptz,sequence_no integer);
 create function private.current_user_is_active() returns boolean language sql as $$select auth.uid() is not null$$;
 create function private.module_task_allowed(uuid) returns boolean language sql as $$select true$$;
 create function private.can_view_task(uuid) returns boolean language sql as $$select exists(select 1 from public.tasks where id=$1 and owner_id=auth.uid())$$;
 create function private.has_permission(text) returns boolean language sql as $$select false$$;
 create function private.project_access(uuid) returns boolean language sql as $$select false$$;
 insert into public.tasks(id,owner_id) values ('${task}','${actor}'),('${other}','30000000-0000-4000-8000-000000000001');
 insert into public.task_activity values ('${task}','submitted','2026-10-02 12:00+00',1),('${task}','reopened','2026-10-05 12:00+00',2),('${other}','submitted','2026-10-01 12:00+00',1),('${other}','reopened','2026-10-07 12:00+00',2);
 alter table public.task_activity enable row level security;grant select on public.task_activity to authenticated;`);
 await db.exec(await readFile(new URL('../supabase/migrations/20261027160323_task_delay_private_summary.sql',import.meta.url),'utf8'));
 await db.exec(`begin;set local role authenticated;select set_config('request.uid','${actor}',true)`);
 const rows=(await db.query("select * from public.task_approval_pause_days($1::uuid[],'Asia/Riyadh')",[[task,other]])).rows;
 assert.deepEqual(rows,[{task_id:task,paused_days:3}]);
 assert.deepEqual((await db.query('select * from public.task_activity')).rows,[],'audit remains hidden');
 assert.equal(calcDelay('2026-10-01',null,'قيد التنفيذ',null,[],new Date('2026-10-06T12:00:00Z'),rows[0].paused_days),2);
 await db.exec('rollback');
 assert.equal((await db.query("select has_function_privilege('anon','public.task_approval_pause_days(uuid[],text)','execute') ok")).rows[0].ok,false);
 console.log('PASS private task delay: authorized aggregate, hidden audit and denied anonymous access');
}finally{await db.close()}
