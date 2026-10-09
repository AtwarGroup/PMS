export function normalizeFollowup(value={}){
 const v={blocked:!!value.blocked,reason:String(value.reason||'').trim(),next_step:String(value.next_step||'').trim(),owner_role:value.owner_role||'assignee',follow_date:value.follow_date||null};
 if(v.reason.length>1000||v.next_step.length>1000)throw Error('السبب والإجراء التالي يجب ألا يتجاوز كل منهما 1000 حرف.');
 if(!['assignee','creator'].includes(v.owner_role))throw Error('اختر صاحب الإجراء.');
 if(v.follow_date){const d=new Date(v.follow_date+'T00:00:00Z');if(!/^\d{4}-\d{2}-\d{2}$/.test(v.follow_date)||!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==v.follow_date)throw Error('موعد المتابعة غير صالح.');}
 return v;
}
