-- Staging rollout: internal solution notices and a supervisor-only summary.
alter table public.notifications add column it_support_ticket_id uuid references private.it_support_tickets(id)on delete set null;
create index notifications_it_support_ticket_idx on public.notifications(it_support_ticket_id);
create table private.it_support_solution_notices(
 ticket_id uuid not null references private.it_support_tickets(id),resolved_at timestamptz not null,
 recipient_id uuid not null references public.profiles(id),reminder_number int not null check(reminder_number>=0),
 sent_at timestamptz not null default now(),primary key(ticket_id,resolved_at,recipient_id,reminder_number)
);
create index it_solution_notice_recipient_idx on private.it_support_solution_notices(recipient_id);
alter table private.it_support_solution_notices enable row level security;
create policy internal_only on private.it_support_solution_notices to authenticated using(false)with check(false);
revoke all on private.it_support_solution_notices from public,anon,authenticated;
create index it_support_confirmation_due_idx on private.it_support_tickets(resolved_at)where state='resolved';
create function private.it_support_solution_notice(p_ticket uuid,p_reminder boolean default false)returns boolean language plpgsql security definer set search_path=pg_catalog,private,public as $$
declare t private.it_support_tickets;recipient uuid;sequence_number int:=0;inserted int;begin
select * into strict t from private.it_support_tickets where id=p_ticket for update;
if t.state<>'resolved'or t.resolved_at is null or t.service_key='purchase'then return false;end if;
recipient:=private.it_support_owner(t.id);if recipient is null or not private.it_actor_ready(recipient)then return false;end if;
if p_reminder then
 if now()<t.resolved_at+interval '24 hours'then return false;end if;
 if exists(select 1 from private.it_support_solution_notices n where n.ticket_id=t.id and n.resolved_at=t.resolved_at and n.recipient_id=recipient and((n.reminder_number=0 and n.sent_at>now()-interval '24 hours')or(n.reminder_number>0 and n.sent_at>now()-interval '48 hours')))then return false;end if;
 sequence_number:=1+floor(extract(epoch from(now()-t.resolved_at-interval '24 hours'))/172800)::int;
end if;
insert into private.it_support_solution_notices(ticket_id,resolved_at,recipient_id,reminder_number)values(t.id,t.resolved_at,recipient,sequence_number)on conflict do nothing returning 1 into inserted;
if inserted is null then return false;end if;
insert into public.notifications(recipient_id,type,title,message,it_support_ticket_id)values(recipient,'IT_SUPPORT',case when p_reminder then 'تذكير بتأكيد الحل — IT-'else 'تم تقديم الحل — IT-'end||t.number,'قدّم قسم تقنية المعلومات حلًا للطلب. جرّب الحل ثم اختر «تأكيد الحل وإغلاق الطلب»، أو «المشكلة مستمرة» إذا لم تُحل المشكلة.',t.id);
return true;end$$;
create function private.it_support_solution_reminders()returns int language plpgsql security definer set search_path=pg_catalog,private as $$declare ticket record;n int:=0;begin
for ticket in select id from private.it_support_tickets where state='resolved'and service_key<>'purchase'and resolved_at<=now()-interval '24 hours'order by resolved_at for update skip locked loop
 if private.it_support_solution_notice(ticket.id,true)then n:=n+1;end if;
end loop;return n;end$$;
create or replace function private.it_support_notify(ticket uuid)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$declare t private.it_support_tickets;u uuid;owner uuid;begin
select * into strict t from private.it_support_tickets where id=ticket;owner:=private.it_support_owner(ticket);
if t.state='resolved'then perform private.it_support_solution_notice(ticket,false);end if;
for u in select distinct x from unnest(array[t.requester_id,t.beneficiary_id,t.specialist_id,owner,case when t.priority=1 and t.service_key<>'purchase'then t.supervisor_id end])x where x is not null and x is distinct from auth.uid()and(t.state<>'resolved'or x is distinct from owner)loop
 if private.it_actor_ready(u)then insert into public.notifications(recipient_id,type,title,message,it_support_ticket_id)values(u,'IT_SUPPORT','تحديث طلب IT-'||t.number,'يوجد تحديث في محادثة الطلب أو إجراء مطلوب منك.',t.id);end if;
end loop;end$$;
create function private.it_support_notification_open(p_id uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,private,public as $$declare ticket uuid;kind text;begin
perform private.require_module('it_support');select it_support_ticket_id into ticket from public.notifications where id=p_id and recipient_id=auth.uid()and type='IT_SUPPORT';
if not found then raise exception 'الإشعار غير متاح'using errcode='42501';end if;
if ticket is not null then if not private.it_support_visible(ticket)then raise exception 'الطلب غير متاح لك حاليًا'using errcode='42501';end if;select service_key into kind from private.it_support_tickets where id=ticket;end if;
update public.notifications set read_at=coalesce(read_at,now())where id=p_id and recipient_id=auth.uid();return jsonb_build_object('ticket_id',ticket,'purchase',coalesce(kind='purchase',false));end$$;
create function public.it_support_notification_open(p_id uuid)returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_notification_open(p_id)$$;
revoke all on function private.it_support_solution_notice(uuid,boolean),private.it_support_solution_reminders(),private.it_support_notification_open(uuid),public.it_support_notification_open(uuid)from public,anon,authenticated;
grant execute on function private.it_support_notification_open(uuid),public.it_support_notification_open(uuid)to authenticated;
