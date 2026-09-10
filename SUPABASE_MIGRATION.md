# ATWAR ONE — Supabase RC4

هذه نسخة اختبار معزولة على Supabase. Firebase Live لا يتم استخدامه تشغيليًا من هذه النسخة ولا يتم تعديله.

## المنقول إلى Supabase
- Supabase Auth + profiles
- المهام والبحث والفلاتر والتفاصيل وWorkflow وإعادة الإسناد
- Activity وSubtasks وNotifications
- Workspace: Quick Notes + Follow-ups
- Team / Profile / Organization / My Day / Search
- Admin profile/role/manager/status updates
- Excel export + transactional Excel import through PostgreSQL RPC

## قبل تشغيل RC4
نفّذ RC4_DATABASE_PATCH.sql مرة واحدة في SQL Editor.

## خارج RC4 حتى الآن
إنشاء مستخدم جديد في Supabase Auth من المتصفح غير مضمّن لأن ذلك يتطلب Server-side Admin API/Edge Function ولا يجوز تضمين Service Role في JavaScript المتصفح.

لا يتم التحويل النهائي من Firebase قبل آخر Export/Delta ومراجعة اختبار القبول.
