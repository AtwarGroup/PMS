# إدارة المشاريع — الدفعة الأولى

قسم مستقل في ATWAR ONE. كل مشروع يجمع الهدف والمخرجات، المدير والمسؤول عن اعتماد المشروع والفريق، المراحل، المهام، جانت بمقياس يوم/أسبوع/شهر، قائمة وكانبان، دردشة مع إشارات وربط مهمة وتحويل الرسالة إلى مهمة، ملفات خاصة، مخاطر وسجل تغييرات.

المهام سجلات من المحرك الحالي، وتظهر لدى المكلف دون نسخ. مدير المشروع يعتمد مهام الأعضاء، والمسؤول عن اعتماد المشروع يعتمد مهام المدير نفسه. لا اعتماد ذاتي؛ المسؤول عن اعتماد المشروع وحده يغلق المشروع بعد اعتماد مهامه ومعالجة العوائق. لا يستطيع العضو تعديل المواعيد؛ مدير المشروع يعيد الجدولة مع سبب ومراجعة المهام المتأثرة. لا تتحرك المهام التالية تلقائيًا. التبعيات تمنع البدء قبل اعتماد السابق وتمنع الحلقات.

التقدم موزون؛ المهام غير المعتمدة تمنع ظهور 100%. وصول المشروع حسب العضوية والمدير والمسؤول عن اعتماد المشروع ومسؤول النظام. صلاحيات المهام العامة القديمة تبقى قائمة، ولا تمنح الاطلاع على دردشة أو ملفات المشروع تلقائيًا. التسجيلات الجديدة لها RLS؛ الملفات في bucket خاص، روابطها قصيرة الصلاحية، ورفعها حتى 10 MB.

الدردشة تعرض أحدث 100 رسالة وتتحدث كل 15 ثانية أثناء ظهور الصفحة. الإشارات والانضمام يصلان إلى جرس الإشعارات. هذه الدفعة لا تتضمن سحب جانت أو تحريك التبعيات تلقائيًا، المسار الحرج، خط أساس، قياس عبء العمل، قوالب المشاريع، أو بحث سجل الدردشة القديم. تغيير المدير والمسؤول عن اعتماد المشروع بعد الإنشاء يحتاج تطويرًا لاحقًا.

التحقق: دورة قبول SQL مع rollback تشمل صلاحيات العضوية والعزل، رفض الإشارة لغير عضو، رفض التبعية الدائرية، منع البدء قبل السابق، تعارض النسخ، ملكية إعادة الجدولة، منع الاعتماد الذاتي، اعتماد المسؤول عن اعتماد المشروع والإغلاق. اختبارات JavaScript تشمل الوزن والمواعيد والتبعيات العابرة وربط اعتماد المهام وستة عروض. المعاينة العامة tests/fixtures/projects.html بيانات اصطناعية ولا تتصل بالحسابات. الفحص البصري داخل حساب حقيقي لم يثبت بعد تعثر الدخول السابق.

## Interface details · 2.5.32

- Project creator owns the delete action, including closed projects. Deletion hides the project and related tasks/files without erasing work or audit events. Server authorization and expected revision are mandatory. A manager who did not create the project cannot delete it.
- Project views poll every 30 seconds; chat polls every 15 seconds. Background view refresh pauses during dirty forms, focused forms and task details. Presence refresh is coalesced, and failed reads display an unknown state.
- The shared authenticated shell records a server-timestamped heartbeat every 45 seconds while the document is visible and online. Project-only presence reads expose member IDs and online flags; heartbeat age over 90 seconds becomes offline. Multi-tab sessions do not mark each other offline. The private table deliberately denies direct client access; its RLS/no-policy informational advisor is expected.
- Project navigation uses underline tabs; job-change requests sit alongside library sections. Policy/job accents reflect document status. Personal notes use a yellow paper surface with readable text and retained save behavior.
- Verification: all JS checks; deployed-database rollback tests in `supabase/tests/project-delete-presence.sql` plus existing project workflow tests. Public preview uses synthetic data and disabled writes.
