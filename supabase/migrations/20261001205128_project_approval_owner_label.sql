do $$ declare s text;begin
s:=pg_get_functiondef('private.project_command(uuid,integer,text,jsonb)'::regprocedure);
s:=replace(s,'اختر مديرًا وراعيًا نشطين','اختر مدير مشروع ومسؤولًا عن اعتماد المشروع بحسابين نشطين');
s:=replace(s,'راعي المشروع وحده يعتمد إغلاقه','المسؤول عن اعتماد المشروع وحده يعتمد إغلاقه');
execute s;
end $$;
