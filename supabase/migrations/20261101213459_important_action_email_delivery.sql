-- Stage clocks prevent chat/file edits from generating duplicate mail or resetting deadlines.
alter table private.it_purchase_requests add column email_stage_since timestamptz not null default now();
alter table private.it_purchase_payments add column email_stage_since timestamptz not null default now();
create function private.important_email_stage_clock()returns trigger language plpgsql set search_path=pg_catalog as $$
begin new.email_stage_since:=now();return new;end$$;
revoke all on function private.important_email_stage_clock()from public,anon,authenticated;
create trigger important_email_purchase_clock before update of phase on private.it_purchase_requests
for each row when(old.phase is distinct from new.phase)execute function private.important_email_stage_clock();
create trigger important_email_payment_clock before update of state,accountant_id on private.it_purchase_payments
for each row when(old.state is distinct from new.state or old.accountant_id is distinct from new.accountant_id)execute function private.important_email_stage_clock();
-- Transactional mail for current important actions only. Never consumes legacy task mail.
create table private.important_email_settings(
 id boolean primary key default true check(id), enabled boolean not null default false,
 activated_at timestamptz not null default now(), worker_token text not null default encode(extensions.gen_random_bytes(32),'hex'),
 function_url text not null default '', last_invoked_at timestamptz, last_request_id bigint
);
insert into private.important_email_settings(id) values(true);
create table private.important_email_outbox(
 id uuid primary key default gen_random_uuid(), event_key text not null unique,
 module text not null, entity_id uuid not null, recipient_id uuid not null references public.profiles(id),
 payload jsonb not null, status text not null default 'pending' check(status in('pending','sending','sent','cancelled','failed')),
 attempts int not null default 0, next_attempt_at timestamptz not null default now(), first_attempt_at timestamptz,
 claimed_at timestamptz, claim_token uuid, batch_id uuid, recipient_email text,
 provider_id text, last_error text, created_at timestamptz not null default now(), sent_at timestamptz
);
create index important_email_pending on private.important_email_outbox(next_attempt_at,created_at) where status in('pending','sending');
alter table private.important_email_settings enable row level security;
alter table private.important_email_outbox enable row level security;
revoke all on private.important_email_settings,private.important_email_outbox from public,anon,authenticated;

-- Resolve owners using the actual workflows, never display names or browser-supplied addresses.
create function private.important_email_actions()
returns table(source_key text,module text,entity_id uuid,recipient_id uuid,subject text,summary text,path text,due_at timestamptz,escalation_id uuid,escalation_at timestamptz)
language sql stable security definer set search_path=pg_catalog,public,private as $$
 select 'fleet:'||r.id||':'||r.state||':'||r.state_changed_at,'fleet',r.id,u,
 case when r.stops_vehicle then 'عاجل: 'else ''end||case when r.state in('awaiting_advance','reimbursement')then 'طلب صيانة بانتظار الصرف'else 'طلب صيانة بانتظار اعتمادك'end||' #'||r.number,
 case r.state when 'awaiting_advance'then 'يرجى صرف الدفعة المعتمدة لاستكمال الصيانة.'when 'reimbursement'then 'يرجى مراجعة مستندات الطلب وتنفيذ الصرف.'else 'يرجى مراجعة طلب الصيانة واتخاذ القرار المطلوب.'end,
 '/fleet/index.html?request='||r.id,r.state_changed_at+make_interval(days=>s.stage_days),
 (select private.fleet_owner()),r.state_changed_at+make_interval(days=>s.stage_days+s.escalation_days)
 from private.fleet_requests r cross join private.fleet_workflow_settings s cross join lateral unnest(private.fleet_request_responsibles(r))u
 where r.state in('quote_exception','fleet_review','increase_review','manager_review','awaiting_advance','reimbursement')
 union all
 select 'fleet-emergency:'||r.id,'fleet',r.id,private.fleet_owner(),'طارئ: توقف مركبة — طلب #'||r.number,
 'يوجد طلب صيانة طارئة لمركبة متوقفة يحتاج متابعة مسؤول الأسطول.','/fleet/index.html?request='||r.id,
 r.created_at+interval '1 day',null::uuid,null::timestamptz from private.fleet_requests r
 where r.stops_vehicle and r.request_type='emergency' and r.state not in('draft','closed','rejected','quote_exception','fleet_review','increase_review','manager_review','awaiting_advance','reimbursement')
 union all
 select 'recruitment-request:'||r.id||':'||r.status||':'||r.stage_started_at,'recruitment',r.id,private.recruitment_owner(r),
 'طلب توظيف بانتظار إجرائك #'||r.number,'يرجى مراجعة طلب التوظيف وتنفيذ المراجعة أو الاعتماد المطلوب.',
 '/recruitment/index.html?request='||r.id,coalesce(t.due_at,private.recruitment_work_due(r.stage_started_at,2)),r.development_id,
 private.recruitment_work_due(coalesce(t.due_at,private.recruitment_work_due(r.stage_started_at,2)),1)
 from private.recruitment_requests r left join private.recruitment_tasks t on t.key='request:'||r.id and not t.done
 where r.status in('department_review','hr_review','finance_review','approval','hr_exception','finance_exception','cancellation_approval')
 union all
 select 'recruitment-offer:'||o.id||':'||o.state||':'||o.stage_started_at,'recruitment',r.id,
 case o.state when 'hr_review'then r.hr_id when 'department_review'then r.department_approver_id when 'development_review'then r.development_id when 'approval'then r.approver_id end,
 'عرض وظيفي بانتظار إجرائك — طلب #'||r.number,'يرجى مراجعة العرض الوظيفي داخل النظام واتخاذ القرار المطلوب.',
 '/recruitment/index.html?request='||r.id,coalesce(t.due_at,private.recruitment_work_due(o.stage_started_at,2)),r.development_id,
 private.recruitment_work_due(coalesce(t.due_at,private.recruitment_work_due(o.stage_started_at,2)),1)
 from private.recruitment_offers o join private.recruitment_applications a on a.id=o.application_id join private.recruitment_requests r on r.id=a.request_id
 left join private.recruitment_tasks t on t.key='offer:'||o.id and not t.done
 where o.state in('hr_review','department_review','development_review','approval')and r.status not in('closed','cancelled')
 union all
 select 'it-critical:'||t.id||':'||t.state_since,'it_support',t.id,private.it_support_owner(t.id),
 'عطل تقني حرج يحتاج المعالجة IT-'||t.number,'يرجى متابعة البلاغ الحرج ومعالجة توقف العمل.',
 '/it-support/index.html?request='||t.id,coalesce(t.due_at,t.state_since+interval '1 day'),t.supervisor_id,coalesce(t.due_at,t.state_since+interval '1 day')+interval '1 day'
 from private.it_support_tickets t where t.priority=1 and t.service_key not in('purchase','suggestion')and t.state in('new','working','waiting_vendor')
 union all
 select 'it-purchase:'||t.id||':'||p.phase||':'||p.quote_version||':'||p.email_stage_since,'it_support',t.id,private.it_support_owner(t.id),
 'طلب شراء تقني بانتظار اعتمادك IT-'||t.number,'يرجى مراجعة طلب الشراء التقني واعتماد عرض السعر.',
 '/it-support/purchases.html?request='||t.id,coalesce(t.due_at,private.recruitment_work_due(t.state_since,2)),t.supervisor_id,
 private.recruitment_work_due(coalesce(t.due_at,private.recruitment_work_due(t.state_since,2)),1)
 from private.it_support_tickets t join private.it_purchase_requests p on p.ticket_id=t.id
 where p.phase in('technical','manager')and t.state not in('closed','cancelled','rejected')
 union all
 select 'it-payment:'||pay.id||':'||pay.state||':'||pay.email_stage_since,'it_support',t.id,private.it_purchase_payment_owner(pay.id),
 case when pay.state='assigned'then 'طلب شراء تقني بانتظار الصرف IT-'else 'دفعة شراء تقني بانتظار اعتمادك IT-'end||t.number,
 'يرجى فتح طلب الشراء لمراجعة الدفعة وتنفيذ الإجراء المطلوب.',
 '/it-support/purchases.html?request='||t.id,private.recruitment_work_due(pay.email_stage_since,2),p.finance_approver_id,private.recruitment_work_due(pay.email_stage_since,3)
 from private.it_purchase_payments pay join private.it_support_tickets t on t.id=pay.ticket_id join private.it_purchase_requests p on p.ticket_id=t.id
 where pay.state in('technical','supervisor','chief','assigned')and t.state not in('closed','cancelled','rejected')
$$;
revoke all on function private.important_email_actions() from public,anon,authenticated;

create function private.important_email_candidates()
returns table(event_key text,module text,entity_id uuid,recipient_id uuid,payload jsonb)
language sql stable security definer set search_path=pg_catalog,public,private as $$
 with actions as materialized(select * from private.important_email_actions()), phases as(
 select a.*,p.phase,p.recipient from actions a cross join lateral(
 select 'initial'phase,a.recipient_id recipient
 union all select 'reminder',a.recipient_id where now()>=a.due_at
 union all select 'escalation',a.escalation_id where now()>=a.escalation_at and a.escalation_id is distinct from a.recipient_id
 )p)
 select a.source_key||':'||a.phase||':'||a.recipient,a.module,a.entity_id,a.recipient,
 jsonb_build_object('subject',case a.phase when 'reminder'then 'تذكير: 'when 'escalation'then 'تصعيد: 'else ''end||a.subject,
 'summary',a.summary,'path',a.path,'due_at',a.due_at,'phase',a.phase)
 from phases a join public.profiles p on p.id=a.recipient
 where p.active and p.status='active'and(p.role='admin'or a.module=any(p.allowed_modules))
 and coalesce(p.email,'')~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 -- A source entering late generates its current initial message, not a backlog of reminders.
 and(a.phase='initial'or exists(select 1 from private.important_email_outbox o where o.event_key=a.source_key||':'||case when a.phase='escalation'then 'reminder'else 'initial'end||':'||a.recipient_id and o.status='sent' and o.sent_at<now()-interval '1 day'))
 union all
 select 'document:'||d.id||':'||d.expires_on||':'||ph.phase||':'||p.id,'fleet',d.id,p.id,
 jsonb_build_object('subject','تنبيهات وثائق المركبات','summary',
 case d.kind when 'authorization'then 'تفويض السائق'when 'registration'then 'رخصة السير'when 'insurance'then 'التأمين'else 'الفحص الدوري'end||' — مركبة '||v.plate||' — الانتهاء '||d.expires_on||' — المتبقي '||(d.expires_on-(now()at time zone'Asia/Riyadh')::date)||' يوم',
 'path','/fleet/index.html?view=documents&vehicle='||v.id,'due_at',d.expires_on,'phase',ph.phase)
 from private.fleet_documents d join private.fleet_alert_settings s on s.kind=d.kind join private.fleet_vehicles v on v.id=d.vehicle_id and v.active
 left join private.hr_employees e on e.id=v.driver_id left join private.hr_employees m on m.id=e.manager_id
 cross join lateral(select case when d.expires_on<(now()at time zone'Asia/Riyadh')::date then 'expired'when d.expires_on<=(now()at time zone'Asia/Riyadh')::date+15 then 'critical'else 'due'end phase)ph
 join public.profiles p on p.id=any(array[private.fleet_owner(),e.profile_id,m.profile_id])
 where d.expires_on<=(now()at time zone'Asia/Riyadh')::date+greatest(s.days_before,15)
 and(d.kind<>'authorization'or d.authorized_driver_id=v.driver_id)
 and p.active and p.status='active'and(p.role='admin'or'fleet'=any(p.allowed_modules))
 and coalesce(p.email,'')~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
$$;
revoke all on function private.important_email_candidates() from public,anon,authenticated;

create function public.important_email_claim(p_token text,p_probe boolean default false)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare cfg private.important_email_settings; item record; batch uuid; lease uuid:=gen_random_uuid(); rows jsonb; recipient uuid;
begin
 select * into strict cfg from private.important_email_settings where id;
 if p_token is null or p_token<>cfg.worker_token then raise exception 'Unauthorized'using errcode='42501';end if;
 if p_probe then return jsonb_build_object('enabled',cfg.enabled,'ready',true);end if;
 if not cfg.enabled then return jsonb_build_object('disabled',true);end if;
 perform pg_advisory_xact_lock(hashtext('important-email-claim'));
 -- Any ambiguous attempt older than 20h is quarantined, never retried past provider dedupe retention.
 update private.important_email_outbox set status='failed',last_error='delivery_unknown_manual_review'where status in('sending','pending')and first_attempt_at<now()-interval '20 hours';
 update private.important_email_outbox set status='pending'where status='sending'and claimed_at<now()-interval '5 minutes';
 -- Cancel obsolete work, renewed documents, changed owners and disabled recipients before sending.
 update private.important_email_outbox o set status='cancelled',last_error='action_no_longer_current'
 where o.status='pending'and not exists(select 1 from private.important_email_candidates()c where c.event_key=o.event_key);
 insert into private.important_email_outbox(event_key,module,entity_id,recipient_id,payload)
 select c.event_key,c.module,c.entity_id,c.recipient_id,c.payload from private.important_email_candidates()c
 where not exists(select 1 from private.important_email_outbox o where o.event_key=c.event_key)
 on conflict(event_key)do nothing;
 select * into item from private.important_email_outbox where status='pending'and next_attempt_at<=now()and attempts<5 order by created_at,id limit 1 for update skip locked;
 if not found then return jsonb_build_object('items','[]'::jsonb);end if;
 batch:=coalesce(item.batch_id,item.id);recipient:=item.recipient_id;
 -- Freeze a document digest on its first attempt so retries use identical content and key.
 if item.batch_id is null then
  update private.important_email_outbox o set batch_id=batch where o.id in(
   select id from private.important_email_outbox where status='pending'and next_attempt_at<=now()and batch_id is null and recipient_id=recipient
   and(case when item.event_key like 'document:%'then event_key like 'document:%'else id=item.id end)order by created_at,id limit 50);
 end if;
 -- A partial cancellation changes a frozen digest: quarantine rather than reuse a provider key with different data.
 if exists(select 1 from private.important_email_outbox where batch_id=batch and status not in('pending','sending'))then
  update private.important_email_outbox set status='cancelled',last_error='digest_changed'where batch_id=batch and status='pending';
  return jsonb_build_object('items','[]'::jsonb);
 end if;
 update private.important_email_outbox o set status='sending',attempts=attempts+1,claimed_at=now(),claim_token=lease,
 first_attempt_at=coalesce(first_attempt_at,now()),recipient_email=coalesce(o.recipient_email,(select lower(btrim(email))from public.profiles where id=o.recipient_id))
 where batch_id=batch and status='pending';
 select jsonb_agg(jsonb_build_object('id',id,'payload',payload)order by event_key)into rows from private.important_email_outbox where batch_id=batch and claim_token=lease;
 return jsonb_build_object('batch_id',batch,'claim_token',lease,'recipient',(select recipient_email from private.important_email_outbox where batch_id=batch limit 1),'items',rows);
end$$;
revoke all on function public.important_email_claim(text,boolean)from public,anon,authenticated;
grant execute on function public.important_email_claim(text,boolean)to service_role;

create function public.important_email_finish(p_batch uuid,p_lease uuid,p_provider text default null,p_error text default null,p_retry boolean default false)
returns void language plpgsql security definer set search_path=pg_catalog,private as $$
begin
 update private.important_email_outbox set status=case when p_provider is not null then 'sent'when p_retry and attempts<5 then 'pending'else 'failed'end,
 provider_id=p_provider,last_error=left(p_error,250),sent_at=case when p_provider is not null then now()end,
 next_attempt_at=now()+make_interval(mins=>least(60,power(2,attempts)::int))
 where batch_id=p_batch and claim_token=p_lease and status='sending';
end$$;
revoke all on function public.important_email_finish(uuid,uuid,text,text,boolean)from public,anon,authenticated;
grant execute on function public.important_email_finish(uuid,uuid,text,text,boolean)to service_role;

create function public.important_email_validate(p_batch uuid,p_lease uuid)returns boolean
language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin
 if not exists(select 1 from private.important_email_settings where id and enabled)then return false;end if;
 if not exists(select 1 from private.important_email_outbox where batch_id=p_batch and claim_token=p_lease and status='sending')then return false;end if;
 if exists(select 1 from private.important_email_outbox o where o.batch_id=p_batch and o.claim_token=p_lease and o.status='sending'
 and not exists(select 1 from private.important_email_candidates()c join public.profiles p on p.id=c.recipient_id
 where c.event_key=o.event_key and lower(btrim(p.email))=o.recipient_email))then
 update private.important_email_outbox set status='cancelled',last_error='changed_before_send'where batch_id=p_batch and claim_token=p_lease and status='sending';return false;
 end if;
 return true;
end$$;
revoke all on function public.important_email_validate(uuid,uuid)from public,anon,authenticated;
grant execute on function public.important_email_validate(uuid,uuid)to service_role;

create extension if not exists pg_net with schema extensions;
-- Scheduler headers contain a private worker credential. Never expose the HTTP queue.
revoke select on net.http_request_queue,net._http_response from public,anon,authenticated;
create function private.invoke_important_email_worker(p_probe boolean default false)returns bigint
language plpgsql security definer set search_path=pg_catalog,private as $$
declare cfg private.important_email_settings; rid bigint;
begin
 select * into strict cfg from private.important_email_settings where id;
 if not p_probe and not cfg.enabled then return null;end if;
 if cfg.function_url!~'^https://[a-z]+\.supabase\.co/functions/v1/send-important-emails$'then raise exception 'Worker URL is not configured';end if;
 select net.http_post(url:=cfg.function_url,headers:=jsonb_build_object('Content-Type','application/json','x-atwar-worker',cfg.worker_token),body:=jsonb_build_object('probe',p_probe),timeout_milliseconds:=120000)into rid;
 update private.important_email_settings set last_invoked_at=now(),last_request_id=rid where id;
 return rid;
end$$;
revoke all on function private.invoke_important_email_worker(boolean)from public,anon,authenticated;
select cron.schedule('atwar-important-action-emails','* * * * *','select private.invoke_important_email_worker();');
