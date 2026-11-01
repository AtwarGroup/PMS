-- A follow-up reply after resolution still notifies its recipient; the initial solution notice is deduplicated separately.
create or replace function private.it_support_notify(ticket uuid)returns void language plpgsql security definer set search_path=pg_catalog,private,public as $$declare t private.it_support_tickets;u uuid;owner uuid;solution_sent boolean:=false;begin
select * into strict t from private.it_support_tickets where id=ticket;owner:=private.it_support_owner(ticket);
if t.state='resolved'then solution_sent:=private.it_support_solution_notice(ticket,false);end if;
for u in select distinct x from unnest(array[t.requester_id,t.beneficiary_id,t.specialist_id,owner,case when t.priority=1 and t.service_key<>'purchase'then t.supervisor_id end])x where x is not null and x is distinct from auth.uid()and(not solution_sent or x is distinct from owner)loop
 if private.it_actor_ready(u)then insert into public.notifications(recipient_id,type,title,message,it_support_ticket_id)values(u,'IT_SUPPORT','تحديث طلب IT-'||t.number,'يوجد تحديث في محادثة الطلب أو إجراء مطلوب منك.',t.id);end if;
end loop;end$$;
