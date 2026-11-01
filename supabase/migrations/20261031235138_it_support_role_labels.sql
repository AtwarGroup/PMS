-- Role labels remain independent of the current employee assigned to the role.
do $$declare definition text;begin definition:=pg_get_functiondef('private.it_purchase_payment_action(uuid,integer,text,jsonb)'::regprocedure);definition:=replace(definition,'راجع أخصائي التقنية طلب الصرف وأحاله لمحمد باسنبل','راجع قسم تقنية المعلومات طلب الصرف وأحاله لمشرف تطوير الأعمال');execute definition;end$$;
