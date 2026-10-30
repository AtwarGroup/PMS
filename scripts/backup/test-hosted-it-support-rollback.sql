-- STAGING ONLY. Existing ownership/settings are read, never changed.
-- Synthetic ticket/file metadata and internal notifications remain uncommitted.
-- Sequences may advance; never reset them on a shared database.
begin;
set local statement_timeout='90s';
set local lock_timeout='5s';
do $test$
declare cfg private.it_support_settings; actor uuid; outsider uuid; administrator uuid;
 ticket uuid; purchase uuid; cancelled uuid; rejected uuid; f jsonb; v jsonb;
 rev int; denied boolean; before_count bigint; before_files bigint; deadline timestamptz;
begin
 select * into strict cfg from private.it_support_settings;
 select id into strict actor from public.profiles p where active and status='active'
  and role<>'admin' and 'it_support'=any(allowed_modules)
  and id not in(cfg.specialist_id,cfg.supervisor_id) order by id limit 1;
 select id into strict outsider from public.profiles p where active and status='active'
  and role<>'admin' and 'it_support'=any(allowed_modules)
  and id not in(actor,cfg.specialist_id,cfg.supervisor_id)
  and not ('it_support.operate'=any(permissions) or 'it_support.supervise'=any(permissions)) order by id limit 1;
 select id into strict administrator from public.profiles where active and status='active' and role='admin' order by id limit 1;
 select count(*) into before_count from private.it_support_tickets;
 select count(*) into before_files from private.it_support_files;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 ticket:=public.it_support_create(jsonb_build_object('service_key','help','title','QA rollback support lifecycle','description','Synthetic support acceptance; never commit','impact',3,'urgency',3));
 assert(select state='new' and approver_id is null and priority=1 and due_at=created_at+interval '4 hours' from private.it_support_tickets where id=ticket),'ordinary support skips approval and P1 is four elapsed hours';
 assert public.it_support_detail(ticket)->'events'='[]'::jsonb,'nonadmin history hidden';
 denied:=false;begin perform public.it_support_action(ticket,1,'comment','{"note":"Synthetic private note","internal":true}');exception when insufficient_privilege then denied:=true;end;assert denied,'requester cannot add internal note';
 denied:=false;begin perform public.it_support_file_prepare(ticket,'qa.exe','application/octet-stream',10);exception when raise_exception then denied:=true;end;assert denied,'unsupported file rejected';
 denied:=false;begin perform public.it_support_file_prepare(ticket,'qa.pdf','application/pdf',10485761);exception when raise_exception then denied:=true;end;assert denied,'oversized file rejected';
 f:=public.it_support_file_prepare(ticket,'qa.pdf','application/pdf',10);
 denied:=false;begin perform public.it_support_file_finish((f->>'id')::uuid);exception when raise_exception then denied:=true;end;assert denied,'unuploaded attachment cannot be completed';
 perform public.it_support_file_abort((f->>'id')::uuid);
 assert not exists(select 1 from private.it_support_files where id=(f->>'id')::uuid),'pending attachment aborted without storage writes';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 denied:=false;begin perform public.it_support_detail(ticket);exception when insufficient_privilege then denied:=true;end;assert denied,'outsider cannot read ticket';
 denied:=false;begin perform public.it_support_action(ticket,1,'working','{"note":"Unauthorized transition"}');exception when insufficient_privilege then denied:=true;end;assert denied,'outsider cannot operate';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',cfg.specialist_id,'role','authenticated')::text,true);
 perform public.it_support_action(ticket,1,'working','{"note":"Synthetic investigation"}');
 denied:=false;begin perform public.it_support_action(ticket,1,'waiting_vendor','{"note":"Stale transition"}');exception when serialization_failure then denied:=true;end;assert denied,'stale revision rejected';
 perform public.it_support_action(ticket,2,'comment','{"note":"Private support investigation","internal":true}');
 perform public.it_support_action(ticket,3,'waiting_employee','{"note":"Synthetic question to requester"}');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 v:=public.it_support_detail(ticket);
 assert not exists(select 1 from jsonb_array_elements(v->'messages') m where (m->>'internal')::boolean),'internal messages hidden from requester';
 perform public.it_support_action(ticket,4,'comment','{"note":"Synthetic requester answer"}');
 assert(select state='working' from private.it_support_tickets where id=ticket),'reply resumes processing';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',cfg.specialist_id,'role','authenticated')::text,true);
 perform public.it_support_action(ticket,5,'waiting_vendor','{"note":"Synthetic vendor wait"}');
 denied:=false;begin perform public.it_support_action(ticket,6,'resolve','{"note":"short"}');exception when raise_exception then denied:=true;end;assert denied,'short solution rejected';
 perform public.it_support_action(ticket,6,'resolve','{"note":"Synthetic solution fully documented"}');
 denied:=false;begin perform public.it_support_action(ticket,7,'close','{"note":"Operator cannot close for requester","rating":5}');exception when insufficient_privilege then denied:=true;end;assert denied,'operator cannot close for requester';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 denied:=false;begin perform public.it_support_action(ticket,7,'close','{"note":"Invalid rating","rating":6}');exception when raise_exception then denied:=true;end;assert denied,'invalid rating rejected';
 perform public.it_support_action(ticket,7,'close','{"note":"Synthetic requester acceptance","rating":5}');
 perform public.it_support_action(ticket,8,'reopen','{"note":"Synthetic repeat issue"}');
 assert(select state='working' and rating is null and resolved_at is null from private.it_support_tickets where id=ticket),'reopen resets resolution/rating';
 purchase:=public.it_support_create(jsonb_build_object('service_key','purchase','title','QA rollback purchase approval','description','Synthetic procurement test; no purchase','impact',2,'urgency',2));
 assert(select state='approval' and due_at is null and sla_started_at is null from private.it_support_tickets where id=purchase),'unapproved procurement has no SLA clock';
 denied:=false;begin perform public.it_support_action(purchase,1,'approve','{"note":"Requester self approval"}');exception when insufficient_privilege then denied:=true;end;assert denied,'purchase requester cannot approve';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',cfg.specialist_id,'role','authenticated')::text,true);
 denied:=false;begin perform public.it_support_action(purchase,1,'working','{"note":"Bypass procurement approval"}');exception when insufficient_privilege then denied:=true;end;assert denied,'operator cannot bypass procurement approval';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',cfg.supervisor_id,'role','authenticated')::text,true);
 perform public.it_support_action(purchase,1,'approve','{"note":"Synthetic procurement approval; no purchase"}');
 assert(select state='new' and due_at is not null and sla_started_at is not null from private.it_support_tickets where id=purchase),'purchase clock starts on approval';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 cancelled:=public.it_support_create(jsonb_build_object('service_key','help','title','QA rollback cancellation','description','Synthetic cancellation only','impact',1,'urgency',1));
 perform public.it_support_action(cancelled,1,'cancel','{"note":"Synthetic requester cancellation"}');
 assert(select state='cancelled' from private.it_support_tickets where id=cancelled),'requester cancellation';
 rejected:=public.it_support_create(jsonb_build_object('service_key','purchase','title','QA rollback purchase rejection','description','Synthetic procurement rejection','impact',1,'urgency',1));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',cfg.supervisor_id,'role','authenticated')::text,true);
 perform public.it_support_action(rejected,1,'reject','{"note":"Synthetic procurement rejection"}');
 assert(select state='rejected' and due_at is null from private.it_support_tickets where id=rejected),'rejected procurement never starts clock';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',administrator,'role','authenticated')::text,true);
 assert jsonb_array_length(public.it_support_detail(ticket)->'events')>0,'admin retains audit';
 assert(select count(*)=before_count+4 from private.it_support_tickets),'only synthetic tickets added inside transaction';
 assert(select count(*)=before_files from private.it_support_files),'no attachment metadata left inside transaction';
end $test$;
select 'PASS hosted IT: ordinary/procurement flows, scopes, internal notes, audit, concurrency, SLA, attachment guards, closure and reopening; ROLLBACK follows' as result;
rollback;
