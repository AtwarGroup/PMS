-- STAGING ONLY: eeaedzisysjarwvolbwq. Read-only diagnostic; no end-to-end SLA claim.
-- Run one operation at a time (the original combined batch can reach its 25-second deadline).
begin read only;
set local statement_timeout='25s';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"719473c6-5354-4775-b6f4-c0239a86c385","role":"authenticated"}',true);
do $bench$
declare op text; i integer; started timestamptz; elapsed numeric; timings numeric[]; discarded jsonb; output jsonb:='[]';
begin
foreach op in array array['active_task_projection'] loop
 timings:='{}';
 for i in 1..30 loop
 started:=clock_timestamp();
 if op='active_task_projection' then
 select coalesce(jsonb_agg(t),'[]') into discarded from(select id,status,assignee_id,creator_id,start_date,due_date,progress,updated_at from public.tasks where deleted_at is null and status<>'مكتملة' order by updated_at desc limit 1000)t;
 elsif op='task_list' then
 select coalesce(jsonb_agg(t),'[]') into discarded from(select * from public.tasks where deleted_at is null and status<>'مكتملة' order by updated_at desc limit 100)t;
 else
 select coalesce(jsonb_agg(a),'[]') into discarded from(select * from public.task_activity where task_id in(select id from public.tasks where deleted_at is null order by updated_at desc limit 30) order by sequence_no limit 200)a;
 end if;
 elapsed:=extract(epoch from(clock_timestamp()-started))*1000;timings:=array_append(timings,elapsed);
 end loop;
 output:=output||(select jsonb_build_array(jsonb_build_object('operation',op,'samples',30,'p50_ms',round(percentile_cont(0.5) within group(order by x)::numeric,2),'p95_ms',round(percentile_cont(0.95) within group(order by x)::numeric,2),'max_ms',round(max(x),2))) from unnest(timings)x);
end loop;
perform set_config('atwar.read_benchmark',output::text,true);
end $bench$;
select current_setting('atwar.read_benchmark')::jsonb as read_only_database_benchmark;
rollback;