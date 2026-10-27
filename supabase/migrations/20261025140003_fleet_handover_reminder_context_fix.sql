-- Keep the context projection aligned when rolling out function-sized migrations.
do $$declare d text;begin
 d:=pg_get_functiondef('private.fleet_operations_context_before_feedback()'::regprocedure);
 d:=replace(d,'h.state=''pending_driver''','h.state in(''pending_driver'',''pending_sender'',''fleet_review'',''pending_receiver'')');
 d:=replace(d,'h.submitted_at<=now()','(case when h.workflow_version=2 then h.updated_at else h.submitted_at end)<=now()');execute d;
end$$;
