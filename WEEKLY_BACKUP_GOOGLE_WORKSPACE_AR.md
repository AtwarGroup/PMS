# إعداد النسخ الاحتياطي الأسبوعي إلى Google Workspace

## السياسة المعتمدة

- الموعد: الجمعة الساعة 2:00 صباحًا بتوقيت السعودية.
- الوجهة: Google Drive التابع للمؤسسة.
- الاحتفاظ: آخر 12 نسخة أسبوعية؛ تُحذف النسخة الثالثة عشرة بعد نجاح رفع النسخة الجديدة.
- التشفير: AES-256 قبل الرفع إلى Google Drive.
- التشغيل: تلقائي، مع إمكانية التشغيل اليدوي من GitHub Actions.

## محتويات كل نسخة

1. قاعدة بيانات Supabase كاملة بصيغة قابلة للاستعادة، بما فيها بيانات المستخدمين وبيانات Storage الوصفية.
2. جميع الملفات الفعلية داخل Supabase Storage.
3. كود النظام وملفات الترحيل من نسخة GitHub المنشورة.
4. تعريفات الأدوار دون كلمات مرور الأدوار.
5. تقرير محتويات وبصمات SHA-256 للتحقق من سلامة النسخة.

## أولًا: إنشاء حساب خدمة Google

1. افتح Google Cloud Console بحساب المؤسسة وأنشئ مشروعًا باسم `ATWAR Backup`.
2. فعّل `Google Drive API`.
3. من `IAM & Admin > Service Accounts` أنشئ حساب خدمة باسم `atwar-backup`.
4. فعّل `Domain-wide delegation` لحساب الخدمة.
5. أنشئ مفتاحًا من نوع JSON ونزّله مرة واحدة.
6. انسخ `OAuth 2 Client ID` الخاص بحساب الخدمة.

## ثانيًا: تفويض الحساب داخل Google Workspace

يجب تنفيذ هذه الخطوات من حساب Super Admin:

1. افتح `Admin Console > Security > Access and data control > API controls`.
2. افتح `Manage Domain Wide Delegation` ثم اختر `Add new`.
3. أدخل Client ID لحساب الخدمة.
4. أدخل النطاق التالي فقط:

   `https://www.googleapis.com/auth/drive.file`

5. اعتمد التفويض.

هذا النطاق يسمح للنظام بإدارة ملفات النسخ التي ينشئها فقط، ولا يمنحه قراءة بقية ملفات Drive.

## ثالثًا: إضافة GitHub Secrets

من المستودع افتح `Settings > Secrets and variables > Actions`، ثم أضف الأسرار التالية في تبويب Secrets:

- `SUPABASE_DB_URL`: رابط Session pooler من Supabase، وليس Transaction pooler.
- `SUPABASE_URL`: رابط المشروع، مثل `https://PROJECT.supabase.co`.
- `SUPABASE_SERVICE_ROLE_KEY`: مفتاح Service Role من إعدادات Supabase API.
- `GDRIVE_SERVICE_ACCOUNT_JSON`: كامل محتوى ملف JSON لحساب الخدمة.
- `GDRIVE_IMPERSONATE_EMAIL`: بريد Workspace الذي سيظهر مجلد النسخ داخل Drive الخاص به.
- `BACKUP_ENCRYPTION_PASSWORD`: عبارة تشفير قوية وفريدة لا تقل عن 32 حرفًا.

ثم من تبويب Variables أضف:

- `GDRIVE_BACKUP_FOLDER` وقيمته المقترحة: `ATWAR ONE Backups`.

لا تضع أيًا من هذه القيم داخل ملفات المستودع، ولا ترسلها عبر البريد أو المحادثات.

## رابعًا: الاختبار الأول

1. افتح `Actions > ATWAR Weekly Encrypted Backup`.
2. اختر `Run workflow`.
3. انتظر نجاح جميع الخطوات.
4. افتح Google Drive للبريد المحدد في `GDRIVE_IMPERSONATE_EMAIL`.
5. تأكد من وجود مجلد `ATWAR ONE Backups` وفيه ملفان بالاسم نفسه:
   - `ATWAR_ONE_DATE.tar.gz.gpg`
   - `ATWAR_ONE_DATE.tar.gz.gpg.sha256`

## استعادة نسخة عند الحاجة

1. نزّل الملف المشفر وملف SHA-256.
2. تحقق من البصمة: `sha256sum -c FILE.gpg.sha256`.
3. فك التشفير باستخدام GPG وعبارة التشفير المحفوظة.
4. فك ملف `tar.gz`.
5. افحص `backup-info.txt` و`manifest.sha256`.
6. استعد قاعدة البيانات إلى مشروع تجريبي أولًا باستخدام `pg_restore`.
7. ارفع ملفات مجلد `storage` إلى الحاويات المطابقة، ثم اختبر الدخول والمهام والمرفقات قبل أي استعادة إنتاجية.

## ضوابط مهمة

- احفظ عبارة التشفير في مدير كلمات مرور المؤسسة؛ فقدانها يعني تعذر فتح النسخ.
- احتفظ بمفتاح JSON في GitHub Secrets فقط، ثم احذف النسخة المحلية بعد نجاح الإعداد.
- عند تغيير كلمة مرور قاعدة البيانات أو تدوير Service Role يجب تحديث GitHub Secrets فورًا.
- راجع نجاح المهمة مرة كل أسبوع، ونفّذ تجربة استعادة على مشروع تجريبي مرة كل ثلاثة أشهر.
