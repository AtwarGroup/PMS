create function private.it_support_supervisor_dashboard()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,private,public as $$declare summary jsonb;queue jsonb;begin
perform private.require_module('it_support');if not private.it_support_permission('it_support.supervise')then raise exception 'لوحة المتابعة لمشرف تطوير الأعمال'using errcode='42501';end if;
select jsonb_build_object(
 'open',count(*)filter(where state not in('closed','cancelled','rejected')),
 'overdue',count(*)filter(where due_at<now()and state not in('closed','cancelled','rejected','resolved','waiting_employee')),
 'escalated',count(*)filter(where state='waiting_vendor'),
 'waiting_information',count(*)filter(where state='waiting_employee'),
 'waiting_confirmation',count(*)filter(where state='resolved'),
 'attention',count(*)filter(where state in('waiting_vendor','waiting_employee','resolved')or(due_at<now()and state not in('closed','cancelled','rejected','resolved','waiting_employee'))),
 'average_resolution_hours',round(avg(greatest(0,extract(epoch from(resolved_at-created_at))-sla_paused_seconds)/3600)filter(where resolved_at>=now()-interval '30 days'),1),
 'resolution_count',count(*)filter(where resolved_at>=now()-interval '30 days'),
 'average_rating',round(avg(rating)filter(where state='closed'and updated_at>=now()-interval '30 days'),1),
 'rating_count',count(rating)filter(where state='closed'and updated_at>=now()-interval '30 days'),
 'period_days',30
 )into summary from private.it_support_tickets where service_key<>'purchase';
select coalesce(jsonb_agg(to_jsonb(q)order by q.priority,q.created_at),'[]'::jsonb)into queue from(
 select t.id,t.number,t.title,t.state,t.priority,t.due_at,t.state_since,t.created_at,t.requester_id,t.beneficiary_id,t.specialist_id,t.supervisor_id,b.full_name beneficiary_name,
 (t.due_at<now()and t.state not in('resolved','waiting_employee'))is_overdue
 from private.it_support_tickets t join public.profiles b on b.id=t.beneficiary_id where t.service_key<>'purchase'and(t.state in('waiting_vendor','waiting_employee','resolved')or(t.due_at<now()and t.state not in('closed','cancelled','rejected','resolved','waiting_employee')))order by t.priority,t.created_at limit 20
 )q;
return jsonb_build_object('summary',summary,'queue',queue,'queue_limit',20);end$$;
create function public.it_support_supervisor_dashboard()returns jsonb language sql security invoker set search_path=pg_catalog,private as $$select private.it_support_supervisor_dashboard()$$;
revoke all on function private.it_support_supervisor_dashboard(),public.it_support_supervisor_dashboard()from public,anon,authenticated;
grant execute on function private.it_support_supervisor_dashboard(),public.it_support_supervisor_dashboard()to authenticated;
