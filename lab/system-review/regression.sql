BEGIN;
update profiles set active=true,status='active' where id='2347fbff-372e-43d1-a2e4-094f5b3159bf';
DO $$ declare t uuid; r uuid; before_due date; begin
perform set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
t:=create_task_safe('اختبار مراجعة النظام','eabb8105-e54d-45a3-90c8-15334698bbfc',p_start_date=>current_date-3,p_due_date=>current_date-1);
perform set_config('request.jwt.claim.sub','eabb8105-e54d-45a3-90c8-15334698bbfc',true);
r:=request_task_reschedule(t,current_date,current_date+3,'تغيير موعد التسليم');
if (select due_date from tasks where id=t)<>current_date-1 then raise exception 'request changed dates before approval';end if;
update profiles set active=false,status='inactive' where id='797d5893-d44d-489c-9109-91da4882acfe';
perform set_config('request.jwt.claim.sub','797d5893-d44d-489c-9109-91da4882acfe',true);
begin perform decide_task_reschedule(r,false,'رفض الاختبار');raise exception 'BUG: inactive creator decided request';exception when insufficient_privilege then null;end;
end $$;
ROLLBACK;
select 'Inactive creator denied' result;
