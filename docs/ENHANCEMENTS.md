# تحسينات شيكاتي | Shekati enhancements

These changes implement the eight improvements requested after the cheque-only interface review. All 113 distinct iPhone scenarios passed and build 6 was signed and uploaded. The optional deletion field is deployed to Production and build 6 is now in internal owner testing; [VALIDATION.md](VALIDATION.md) records schema and distribution evidence. The owner reports build 6 installed and opened; [owner report](build6-device-state.json). The owner reports synced status/last-sync time and correct single deletion/restoration; [owner report](build6-device-state.json). [Production metadata](build6-private-save-state.json) independently confirms a successful private native cheque-save operation. Cross-device sync, camera/OCR and closed-app device alerts remain unverified. The existing HTML preview shows the earlier simplified design; use the native build to exercise these features.

## الاستخدام اليومي

1. **إدخال أسرع:** اقتراح أسماء وبنوك سبق إدخالها، و«حفظ وإضافة شيك آخر». الاحتفاظ بالنوع والبنك والاسم اختياري؛ يُمسح المبلغ والرقم والصور، وتجب مراجعة استحقاق الشيك التالي. الأزرار «التالي/تم» تساعد في التنقل بين الحقول.
2. **صرف وتحصيل واضح:** زر ظاهر قرب المبلغ، وإجراء سريع من صف الشيك. تظهر نافذة تطلب التاريخ الفعلي، وتختار اليوم افتراضيًا. مرور الاستحقاق يبقي الشيك غير مسدّد.
3. **قائمة مرتبة:** الاختيار الافتراضي «غير المسدّدة»، مع «الكل والسجل». اختيار العرض محفوظ. تظهر اختصارات اليوم، والأسبوع، والمتأخرة، وزر لمسح البحث والفلاتر. تُعرض المدة المتبقية مع تاريخ يوم/شهر/سنة.
4. **أخطاء أقل:** إجماليات الوارد والصادر منفصلة، وتنبيه عند تشابه شيكين يسمح بمراجعة الموجود أو الحفظ المقصود. يظهر خطأ المبلغ بجانب الحقل، وتُفحص العلاقة بين الإصدار والاستحقاق والتاريخ الفعلي.

## الحذف والملفات

5. **استعادة آمنة:** الحذف ينقل الشيك إلى «المحذوفة مؤخرًا» ويوقف تذكيراته. يمكن التراجع أو الاستعادة خلال 30 يومًا. بعد انتهاء الفترة يبقى السجل في السلة للحذف النهائي يدويًا؛ لا يوجد تنظيف تلقائي قد يحذف صورة دون مراجعة. الحذف النهائي يحتاج تأكيدًا ويُزامَن عبر iCloud.

   من الإعدادات ← البيانات والنسخ الاحتياطي، أنشئ ملفًا مشفّرًا بكلمة مرور من 10 أحرف على الأقل. يشمل الصور والعملة والترتيب وحالات الحذف وخيارات التذكير. تُعرض معاينة عند الاستعادة، وتبقى السجلات الحالية دون استبدال افتراضيًا. استعادة إعدادات التذكير العامة اختيار مستقل، ولا تستعيد لغة الجهاز أو قفل التطبيق. كلمة المرور غير محفوظة ولا يمكن استرجاعها.

6. **Excel وتقارير:** صدّر CSV أو نزّل القالب ثم استورد ملفًا مع معاينة الصفوف والأخطاء والتكرار. الصفوف غير الصالحة لا تُحفظ، والتكرار مستبعد افتراضيًا. استخدم أسماء الأعمدة الإنجليزية وتواريخ YYYY-MM-DD والعملة المختارة. تُحمى الحقول النصية بعلامة نص لتجنب تنفيذ صيغ الجداول والحفاظ على الأصفار؛ لا تحذف عمود `_format` من ملفات شيكاتي عند إعادة استيرادها.

   من قائمة الشيكات ← كشف الشيكات، احفظ PDF أو CSV للصفوف الظاهرة وترتيبها الحالي. اختر البنك وفترة الاستحقاق قبل فتح الكشف. يعرض PDF الاسم والرقم والبنك والنوع والحالة والمبلغ والتاريخ، مع إجماليات منفصلة وصفحات متعددة. ملفات PDF وCSV تتضمن معلومات مقروءة؛ اختر مكان الحفظ والمشاركة بعناية.

## التنبيهات والكفاءة

7. **تغطية واضحة:** تفاصيل الشيك تعرض أقرب تذكير مستقبلي وافق نظام iOS على جدولته فعلًا. يوضح التطبيق الحالات التي لا يوجد فيها تذكير مقبل. تبقى التنبيهات المستلمة غير المراجعة ما دامت تفاصيلها صالحة؛ الصرف والحذف وتغيير البيانات أو الخصوصية يزيل التنبيه القديم. «ذكّرني بعد ساعة» يعمل من إشعار الشيك بعد مصادقة الجهاز، ويترك الاستحقاق كما هو. يحتسب التذكير المؤجل ضمن سقف 60 طلبًا؛ الأولوية للأقرب، وقد تبقى بعض المواعيد خارج التغطية حتى تفتح التطبيق.
8. **كفاءة مقاسة:** اشتقاق الصفوف والترتيب والإجماليات مرة واحدة لكل تحديث، وإعادة استخدام منسّقات العرض، وعدم إعادة كتابة التنبيهات المتطابقة. استيراد CSV والتشفير وفك التشفير تعمل خارج مسار الواجهة. اختبارات القياس تشمل 1,000 و10,000 شيك، وسجلًا على القرص لألف شيك مع 2,000 صورة JPEG. نتائج المحاكي لا تحل محل قياس التمرير والذاكرة على أقدم آيفون مدعوم.

عند وجود أكثر من 59 تنبيه شيك في اللحظة نفسها، لا يكفي فتح التطبيق قبل الموعد لتغطيتها جميعًا؛ تبقى أولوية الطابور للأقرب مع تذكير التغطية. راجع قائمة اليوم داخل التطبيق، ولا تعتمد على وصول إشعار منفصل لكل شيك عند كثرة المواعيد المتزامنة.

## Technical and recovery boundaries

- The original SwiftData entity names and every existing attribute remain intact. Only optional `ChequeRecord.deletedAt` is added. A frozen build-5 populated-store migration test verifies currency, leading zeros, reminder choices and external images after reopening.
- Currency changes remain blocked when any records exist, including the trash. Incoming/outgoing sums retain exact minor units and independent overflow detection; conflicting currencies suppress totals.
- Backups use an authenticated versioned header, random salt and nonce, PBKDF2-HMAC-SHA256 with 600,000 iterations, and AES-256-GCM through Apple OS cryptographic APIs. Plaintext JSON is held in memory only. Wrong passwords and altered ciphertext fail before record mutation. The password is neither saved nor uploaded.
- Backup files are limited to 256 MB, with a conservative 160 MB image/text preflight before encoding and 20 MB per image. CSV is limited to 5,000 data rows and 10 MB. Large files are rejected explicitly; no partial backup is written.
- Backup restoration merges by UUID in one save. Matching existing records remain intact unless the user explicitly enables replacement. Exported CSV is a data transfer format without images or per-cheque reminder settings; encrypted backup is the full recovery format.
- The exported report freezes the filtered snapshots when it opens, so an iCloud update does not silently change a report being saved.
- The additive deletion field is deployed to Production before owner distribution. A successful native private save operation is verified, and the owner reports synced status and single restoration. Cross-device sync, camera/OCR, closed-app notification delivery, snooze and authenticated notification routing remain device checks in [DEVICE_QA.md](DEVICE_QA.md).
- Update every participating iPhone to build 6 or newer before testing recently deleted records through iCloud. Build 5 does not understand the deletion marker and can still display/remind about a record moved to the trash by the newer app.

## Encryption declaration

The backup uses CryptoKit/CommonCrypto supplied by iOS and no bundled cryptographic implementation. The existing `ITSAppUsesNonExemptEncryption = NO` declaration is retained for this OS-only implementation, following [Apple's encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/). Re-evaluate this declaration if a future build introduces a third-party or custom cryptographic implementation.
