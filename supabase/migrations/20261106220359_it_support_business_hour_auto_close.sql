-- Approved workweek: Saturday through Thursday, Friday excluded.
update private.it_support_settings set work_days=array[6,0,1,2,3,4];
-- Automated system messages have no human actor. Existing readers use a left join.
alter table private.it_support_messages alter column actor_id drop not null;
do $$declare definition text;begin
 select pg_get_functiondef('private.it_support_detail(uuid)'::regprocedure)into definition;
 execute replace(definition,'join public.profiles p on p.id=m.actor_id','left join public.profiles p on p.id=m.actor_id');
end$$;
-- Deadlines are fixed using the configured Riyadh business calendar.
alter table private.it_support_tickets add column confirmation_started_at timestamptz,
 add column confirmation_reminder_at timestamptz,add column auto_close_at timestamptz,
 add column confirmation_reminded_at timestamptz,add column auto_closed_at timestamptz;
create index it_confirmation_auto_close_idx on private.it_support_tickets(auto_close_at) where state='resolved'and auto_close_at is not null;
create function private.it_support_confirmation_clock()returns trigger language plpgsql security definer set search_path=pg_catalog,private as $$begin
 if new.state='resolved'and new.service_key not in('purchase','suggestion')then
  if tg_op='INSERT'or old.state is distinct from 'resolved'or new.resolved_at is distinct from old.resolved_at then
   new.confirmation_started_at:=now();new.confirmation_reminder_at:=private.it_work_add(now(),1440);new.auto_close_at:=private.it_work_add(now(),2880);new.confirmation_reminded_at:=null;new.auto_closed_at:=null;
  end if;
 else new.confirmation_started_at:=null;new.confirmation_reminder_at:=null;new.auto_close_at:=null;new.confirmation_reminded_at:=null;if new.state<>'closed'then new.auto_closed_at:=null;end if;
 end if;return new;
end$$;
create trigger it_confirmation_clock before insert or update of state,resolved_at on private.it_support_tickets for each row execute function private.it_support_confirmation_clock();
-- Keep suggestion follow-ups unchanged, while support gets one deadline reminder.
do $$declare definition text;begin
 select pg_get_functiondef('private.it_support_solution_notice(uuid,boolean)'::regprocedure)into definition;
 execute replace(definition,'FUNCTION private.it_support_solution_notice(','FUNCTION private.it_support_solution_notice_before_auto_close(');
 select pg_get_functiondef('private.it_support_action(uuid,integer,text,jsonb)'::regprocedure)into definition;
 execute replace(definition,'FUNCTION private.it_support_action(','FUNCTION private.it_support_action_before_auto_close(');
end$$;
create or replace function private.it_support_solution_notice(p_ticket uuid,p_reminder boolean default false)returns boolean language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare t private.it_support_tickets;recipient uuid;inserted int;begin
 select * into strict t from private.it_support_tickets where id=p_ticket for update;
 if t.state<>'resolved'or t.service_key='purchase'then return false;end if;
 if t.auto_close_at is null then return private.it_support_solution_notice_before_auto_close(p_ticket,p_reminder);end if;
 recipient:=private.it_support_owner(t.id);if recipient is null or not private.it_actor_ready(recipient)then return false;end if;
 if p_reminder and(now()<t.confirmation_reminder_at or now()>=t.auto_close_at or t.confirmation_reminded_at is not null)then return false;end if;
 insert into private.it_support_solution_notices(ticket_id,resolved_at,recipient_id,reminder_number)
 values(t.id,t.confirmation_started_at,recipient,case when p_reminder then 1 else 0 end)on conflict do nothing returning 1 into inserted;
 if inserted is null then return false;end if;
 if p_reminder then update private.it_support_tickets set confirmation_reminded_at=now()where id=t.id;end if;
 insert into public.notifications(recipient_id,type,title,message,it_support_ticket_id)values(recipient,'IT_SUPPORT',case when p_reminder then 'تذكير قبل الإغلاق التلقائي — IT-'else 'تم تقديم الحل — IT-'end||t.number,
 'جرّب الحل ثم اختر «تأكيد الحل وإغلاق الطلب» أو «المشكلة لم تُحل». سيُغلق الطلب تلقائيًا بعد 48 ساعة عمل دون إجراء منك، في '||to_char(t.auto_close_at at time zone 'Asia/Riyadh','YYYY/MM/DD HH24:MI')||' بتوقيت الرياض. تُستثنى ساعات خارج الدوام والإجازات.',t.id);return true;
end$$;
-- Reuse the guarded action implementation; only a public employee reply renews the clock.
create or replace function private.it_support_action(p_id uuid,p_revision integer,p_action text,p_data jsonb)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$declare t private.it_support_tickets;begin
 perform private.it_support_action_before_auto_close(p_id,p_revision,p_action,p_data);
 if p_action='comment'and not coalesce((p_data->>'internal')::boolean,false)then
  select * into strict t from private.it_support_tickets where id=p_id for update;
  if t.state='resolved'and t.auto_close_at is not null and(auth.uid()in(t.requester_id,t.beneficiary_id)or auth.uid()=private.it_support_owner(t.id))then
   update private.it_support_tickets set confirmation_started_at=now(),confirmation_reminder_at=private.it_work_add(now(),1440),auto_close_at=private.it_work_add(now(),2880),confirmation_reminded_at=null where id=t.id;
   perform private.it_support_system(t.id,'تم تجديد مهلة تأكيد الحل لمدة 48 ساعة عمل بعد رد الموظف.');
   perform private.it_support_solution_notice(t.id,false);
  end if;
 end if;
end$$;
create or replace function private.it_support_solution_reminders()returns integer language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare candidate record;t private.it_support_tickets;recipient uuid;operator_id uuid;locked_count int;n int:=0;begin
 -- Match the employee-action profile -> ticket lock order. Skip busy tickets for the next run.
 for candidate in select id,requester_id,beneficiary_id,specialist_id,supervisor_id from private.it_support_tickets where state='resolved'and service_key<>'purchase'and((auto_close_at is not null and((confirmation_reminder_at<=now()and confirmation_reminded_at is null)or auto_close_at<=now()))or(auto_close_at is null and resolved_at<=now()-interval '24 hours'))order by resolved_at loop
  select count(*)into locked_count from(select id from public.profiles where id in(candidate.requester_id,candidate.beneficiary_id,candidate.specialist_id,candidate.supervisor_id)order by id for update skip locked)locked;
  if locked_count<(select count(distinct x)from unnest(array[candidate.requester_id,candidate.beneficiary_id,candidate.specialist_id,candidate.supervisor_id])x where x is not null)then continue;end if;
  select * into t from private.it_support_tickets where id=candidate.id for update skip locked;
  if not found or t.state<>'resolved'or t.service_key='purchase'then continue;end if;
  if t.auto_close_at is not null and t.auto_close_at<=now()then
   recipient:=private.it_support_owner(t.id);
   update private.it_support_tickets set state='closed',state_since=now(),updated_at=now(),auto_closed_at=now(),revision=revision+1 where id=t.id;
   insert into private.it_support_events(ticket_id,actor_id,action,note)values(t.id,null,'auto_close','أُغلق الطلب آليًا بعد 48 ساعة عمل دون إجراء من صاحب الطلب؛ لم يُسجّل تقييم خدمة تلقائي.');
   perform private.it_support_system(t.id,'أُغلق الطلب تلقائيًا بعد انتهاء مهلة 48 ساعة عمل دون إجراء من صاحب الطلب. يمكنك إعادة فتحه إذا استمرت المشكلة.');
   for operator_id in select distinct x from unnest(array[t.requester_id,t.beneficiary_id,t.specialist_id,recipient])x where x is not null loop
    if private.it_actor_ready(operator_id)then insert into public.notifications(recipient_id,type,title,message,it_support_ticket_id)values(operator_id,'IT_SUPPORT','إغلاق تلقائي للطلب — IT-'||t.number,'انتهت مهلة تأكيد الحل (48 ساعة عمل) دون إجراء؛ أُغلق الطلب تلقائيًا. يمكنك إعادة فتحه إذا استمرت المشكلة.',t.id);end if;
   end loop;n:=n+1;
  elsif private.it_support_solution_notice(t.id,true)then n:=n+1;
  end if;
 end loop;return n;
end$$;
revoke all on function private.it_support_confirmation_clock(),private.it_support_solution_notice_before_auto_close(uuid,boolean),private.it_support_action_before_auto_close(uuid,integer,text,jsonb),private.it_support_solution_notice(uuid,boolean),private.it_support_solution_reminders() from public,anon,authenticated;
-- Existing active resolutions receive a full fresh grace period, never retrospective closure.
update private.it_support_tickets set confirmation_started_at=now(),confirmation_reminder_at=private.it_work_add(now(),1440),auto_close_at=private.it_work_add(now(),2880),confirmation_reminded_at=null where state='resolved'and service_key not in('purchase','suggestion');
do $$declare ticket record;begin for ticket in select id from private.it_support_tickets where state='resolved'and auto_close_at is not null loop perform private.it_support_solution_notice(ticket.id,false);end loop;end$$;

-- Reuse the existing scheduler, now every five minutes (maximum normal delivery lag).
do $$begin if to_regprocedure('cron.schedule(text,text,text)')is not null then perform cron.schedule('it-support-solution-reminders','*/5 * * * *','select private.it_support_solution_reminders();');end if;end$$;
