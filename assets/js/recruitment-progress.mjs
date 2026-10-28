export const approvalSteps = [
 ['draft','مسودة'],['department_review','موافقة مدير الإدارة'],['hr_review','مراجعة مسؤول التوظيف'],['approval','اعتماد الاحتياج'],['open','الترشيح والمقابلات والتعيين'],['closed','مكتمل'],
];
const owners={draft:'created_by',rejected:'created_by',department_review:'department_approver_id',hr_review:'hr_id',finance_review:'finance_id',approval:'approver_id',hr_exception:'development_id',finance_exception:'approver_id',cancellation_approval:'approver_id'};
const actions={draft:'استكمال الطلب وإرساله للموافقات',rejected:'مراجعة سبب الرفض وتعديل الطلب أو طلب الاستثناء المتاح',department_review:'مراجعة الاحتياج واتخاذ القرار',hr_review:'مراجعة نوع الاحتياج والتوطين وأهلية المهنة',finance_review:'مراجعة الميزانية والتكلفة واتخاذ القرار',approval:'مراجعة الاحتياج واعتماده',hr_exception:'مراجعة استثناء شؤون الموظفين',finance_exception:'مراجعة الاستثناء المالي',cancellation_approval:'اتخاذ قرار إلغاء الطلب',closed:'اكتمل التعيين والعدد المطلوب',cancelled:'أُلغي الطلب'};
export function progress(r,tasks=[]){
 const pending=tasks.filter(t=>t.request_id===r.id&&!t.done).sort((a,b)=>new Date(a.due_at)-new Date(b.due_at));
 const terminal=['closed','cancelled'].includes(r.status);
 const ownerIds=terminal?[]:r.status==='open'?[...new Set(pending.map(t=>t.owner_id).filter(Boolean))]:[r[owners[r.status]]].filter(Boolean);
 const index=approvalSteps.findIndex(([k])=>k===r.status);
 const current=index>=0?index:({hr_exception:2,finance_exception:3,cancellation_approval:4})[r.status];
 return {pending,terminal,ownerIds:ownerIds.length||terminal?ownerIds:[r.recruiter_id].filter(Boolean),current,
 action:actions[r.status]||(pending.length?'تنفيذ الإجراءات المعلقة أدناه':r.route==='referral'?'مراجعة السير الذاتية المقدمة من الإدارة وتنسيق المقابلات':'توفير المرشحين ومتابعة إجراءات التوظيف'),
 since:r.stage_started_at||pending.find(t=>t.started_at)?.started_at||(r.status==='draft'?r.created_at:null)};
}
export function elapsed(value,now=Date.now()){
 const start=Date.parse(value);if(!Number.isFinite(start))return 'غير متوفر';
 const minutes=Math.max(0,Math.floor((now-start)/60000));
 return minutes<60?`${minutes} دقيقة`:minutes<1440?`${Math.floor(minutes/60)} ساعة و${minutes%60} دقيقة`:`${Math.floor(minutes/1440)} يوم و${Math.floor(minutes%1440/60)} ساعة`;
}

// Task navigation follows its application/interview rather than reopening its parent request.
export function taskDestination(task, interviews = [], actor) {
 if (!task || task.done) return {kind:'unavailable'};
 if (!task.application_id) return {kind:'request',id:task.request_id};
 const interview=interviews.find(i=>task.key===`interview:${i.id}`&&i.application_id===task.application_id&&i.state==='scheduled');
 if(interview&&interview.interviewer_id===actor) return {kind:'interview',id:task.application_id,interview};
 if(task.key===`second-interview:${task.application_id}`&&task.owner_id===actor) return {kind:'second-interview',id:task.application_id};
 return {kind:'application',id:task.application_id};
}
