# إعداد النسخ الاحتياطي الأسبوعي إلى Gmail Google Drive

## الحساب والسياسة المعتمدة

- الحساب: `atwar4sites@gmail.com`.
- الموعد: الجمعة الساعة 2:00 صباحًا بتوقيت السعودية.
- الاحتفاظ: آخر 12 نسخة أسبوعية فقط.
- الوجهة الافتراضية: `ATWAR ONE Backups` في Google Drive.
- التشفير: AES-256 قبل الرفع.

## محتويات النسخة

قاعدة بيانات Supabase وحسابات الدخول، جميع ملفات Supabase Storage، كود النظام وملفات الترحيل، الأدوار دون كلمات مرور، وتقرير تحقق وبصمات SHA-256.

## الربط الآمن بحساب Gmail

1. في مشروع Google Cloud المسمى `ATWAR Backup` فعّل Google Drive API.
2. افتح Google Auth Platform وأنشئ OAuth Client من نوع `Desktop app` باسم `ATWAR Backup rclone`.
3. نزّل rclone على جهاز موثوق وشغّل `rclone config`.
4. أنشئ remote باسم `gdrive` واختر Google Drive.
5. أدخل Client ID وClient Secret اللذين أنشأتهما.
6. اختر النطاق `drive.file` ثم وافق من حساب `atwar4sites@gmail.com`.
7. لا تستخدم حساب الخدمة أو Domain-wide Delegation؛ فهما غير مطلوبين لحساب Gmail الشخصي.

روابط Branding المعتمدة:

- الصفحة الرئيسية: `https://one.atwargroup.com/`
- سياسة الخصوصية: `https://one.atwargroup.com/privacy.html`

## تحويل إعداد rclone إلى GitHub Secret

من PowerShell على الجهاز الذي تم عليه الربط:

```powershell
$config = rclone config file | Select-Object -Last 1
[Convert]::ToBase64String([IO.File]::ReadAllBytes($config)) | Set-Clipboard
```

أضف النص المنسوخ في GitHub Secret باسم `RCLONE_CONFIG_BASE64`، ثم امسح الحافظة وأغلق PowerShell.

## GitHub Secrets المطلوبة

- `SUPABASE_DB_URL`: رابط Session pooler وليس Transaction pooler.
- `SUPABASE_URL`: رابط مشروع Supabase.
- `SUPABASE_SERVICE_ROLE_KEY`: مفتاح Service Role.
- `RCLONE_CONFIG_BASE64`: إعداد OAuth المشفر بصيغة Base64.
- `BACKUP_ENCRYPTION_PASSWORD`: عبارة قوية وفريدة لا تقل عن 32 حرفًا.

وفي Variables أضف `GDRIVE_BACKUP_FOLDER` بقيمة `ATWAR ONE Backups`.

## الاختبار الأول

افتح `Actions > ATWAR Weekly Encrypted Backup > Run workflow`. بعد النجاح تأكد من ظهور ملف `.gpg` وملف `.sha256` داخل المجلد المحدد في Drive.

## تنبيهات

- انشر تطبيق OAuth في وضع Production قبل التشغيل الدائم حتى لا تنتهي صلاحية Refresh Token التجريبية بعد مدة قصيرة.
- لا ترسل Client Secret أو ملف rclone أو مفاتيح Supabase في المحادثات.
- احتفظ بعبارة التشفير في مدير كلمات مرور؛ فقدانها يمنع فتح النسخ.
