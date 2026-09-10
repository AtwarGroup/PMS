ATWAR ONE - Production 1.6

الحالة:
- قاعدة البيانات النهائية: 159 مهمة، 441 سجل نشاط، 32 مهمة فرعية، 0 إشعارات تاريخية.
- Firebase لم يعد مصدر التشغيل بعد الـCutover.
- الموقع يعتمد Supabase Auth + PostgreSQL + RLS.

قبل الرفع النهائي للموقع:
1) انشر Edge Function باسم admin-create-user من:
   supabase/functions/admin-create-user/index.ts
2) لا تضع Service Role Key داخل ملفات HTML/JS.
3) بعد نشر الوظيفة اختبر إنشاء مستخدم واحد من حساب Helpdesk (admin).
4) إذا نجح، ارفع محتويات هذه الحزمة إلى الاستضافة.

اختبار Go-Live المختصر:
- تسجيل الدخول بحساب موظف.
- فتح مهمة وتحديثها.
- تسجيل الدخول بحساب مدير واعتماد/إعادة مهمة.
- تسجيل الدخول بحساب Helpdesk وتجربة إنشاء مستخدم.
