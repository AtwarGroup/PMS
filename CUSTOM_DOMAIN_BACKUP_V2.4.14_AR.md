# إصدار ATWAR ONE V2.4.14

## ما يتضمنه التحديث

- تثبيت النطاق الرسمي `one.atwargroup.com` عبر ملف `CNAME` حتى لا يُفقد عند النشر لاحقًا.
- إضافة صفحة سياسة الخصوصية العامة المطلوبة لإعداد Google OAuth.
- تحديث روابط Branding إلى النطاق الرسمي.
- تحديث روابط الصفحة الرئيسية في النماذج الوظيفية القديمة.
- إعداد النسخ الاحتياطي الأسبوعي المشفر إلى Google Drive لحساب Gmail.
- الاحتفاظ بآخر 12 نسخة أسبوعية وحذف الأقدم تلقائيًا.

## بعد رفع الملفات

1. انتظر اكتمال GitHub Pages.
2. تحقق من `https://one.atwargroup.com/privacy.html`.
3. استخدم في Google Auth Platform:
   - Home page: `https://one.atwargroup.com/`
   - Privacy policy: `https://one.atwargroup.com/privacy.html`
4. أكمل إعداد أسرار GitHub حسب `WEEKLY_BACKUP_GMAIL_AR.md`.

لا تحتوي الحزمة على كلمات مرور أو مفاتيح OAuth أو مفاتيح Supabase.
