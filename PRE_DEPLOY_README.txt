ATWAR ONE — V0.23 PRE-DEPLOY
================================

الحالة
------
هذه الحزمة وصلت إلى مرحلة ما قبل الرفع.
لا توجد Features جديدة في V0.23.

ENTRY POINT
-----------
landing.html

التدفق
------
landing.html
→ نظام أطوار
→ login.html
→ index.html
→ حسب الصلاحية:
   - الرئيسية
   - المهام
   - ملاحظاتي
   - المتابعات
   - الفريق (للمدير وما فوق)
   - ملفي الوظيفي

بوابة الأنظمة
-------------
ZenHR:
https://app.zenhr.com/

Odoo:
https://atwar.odoo.com/odoo

صفحة المهام
-----------
tasks/index.html = LOCKED

تمت مقارنة SHA-256:
Original Tasks.html:
4492d76579d09ac647b5bc234d349097bc9fad604782a2ee57666e4e938a4aec

Pre-Deploy tasks/index.html:
4492d76579d09ac647b5bc234d349097bc9fad604782a2ee57666e4e938a4aec

مطابقة حرفياً:
True

مهم قبل الرفع
-------------
1. لا تستبدل tasks/index.html بأي نسخة أخرى.
2. ارفع هيكل المجلدات كاملًا وليس صفحات منفردة.
3. لا تحذف assets/ أو المجلدات الفرعية.
4. بعد الرفع اختبر من landing.html وليس من صفحة داخلية مباشرة.
5. اختبر الحسابات والصلاحيات قبل أي ربط إضافي.
6. هذه الحزمة لا تنفذ أي تغييرات على النظام Live أثناء التحضير.

نتيجة الفحص
-----------
Missing required files: 0
Broken local links found: 0
Tasks locked and identical: True
Portal links present: True
Simplified Home sections removed: True
