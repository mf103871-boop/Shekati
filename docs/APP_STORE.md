# مواد المتجر | App Store material

Publication draft for version 1.0.0. Replace operator/contact placeholders and check feature claims against physical-iPhone results before public submission. Build 6 at [source 7c5c1a9c](https://github.com/mf103871-boop/Shekati/commit/7c5c1a9c68b4a001fec2a51e8bf198c538089d57) passed all 113 iPhone scenarios and signed archive/export/upload in the [complete pipeline](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531). Apple confirmed build 6 processing state `VALID` through its API at 03:33:14 UTC. Owner-group assignment and installation remain pending; the browser session requires sign-in. The new optional deletion field requires additive Production deployment before owner-group distribution; build 5 remains the last available owner beta. Public App Review has not been requested. Configuration items described as saved below were verified during the earlier account setup.

Historical build **1.0.0 (5)** at [8f806ae](https://github.com/mf103871-boop/Shekati/commit/8f806ae2a3d370dcab6c1cc7597c9d4a8d503ce6) contains the simplified cheque interface. Its [native validation job](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467/job/111323630876) passed 58 distinct iPhone tests and a separate 24-test macOS suite. Signed upload and owner-group assignment passed; [availability proof](screenshots/Shekati-TestFlight-build5.jpg). Historical screenshots below document that version; current enhancement screenshots and validation will be listed in [VALIDATION.md](VALIDATION.md).

## Store configuration

| Field | Value |
| --- | --- |
| Product | Paid app download; all features included |
| US base price | $9.99, saved in App Store Connect; [confirmation image](screenshots/Shekati-price-saved.jpg) |
| Local prices | Price schedule configured across 175 storefronts with corresponding local prices |
| Primary category | Finance |
| Secondary category | Productivity |
| Device | iPhone only; signed build 5 archive and IPA family `[1]` guards passed |
| Mac and Apple Vision Pro availability | Unchecked and saved in App Store Connect |
| Reduced school volume price | Unchecked and saved |
| Paid Apps Agreement | Active, verified read-only; 25 September 2026–3 September 2027 |
| Free Apps Agreement | Active, verified read-only |
| US Foreign Status and W-8BEN | Active, verified read-only |
| DSA | Active, verified read-only |
| Brazil tax form | Missing tax information; not changed during setup |
| Internal testing group | `Shekati Owner Testing` attached to builds 5, 4 and 2: three builds and one owner tester, automatic distribution off |
| Owner invitation | Sent on 3 October 2026; portal now reports `Installed 1.0.0 (5)` on 4 October, iPhone 17 Pro Max / iOS 26.6.1; physical runtime acceptance pending |
| TestFlight build | Version 1.0.0, build 5 available; [portal proof](screenshots/Shekati-TestFlight-build5.jpg) |
| Internal TestFlight readiness | Group Builds tab: build 5 `Testing`, `Expires in 90 days`; portal-reported installation confirmed, device acceptance pending |
| iCloud schema | Original phone initialization/Production parity verified; [historical proof](screenshots/Shekati-iCloud-production-schema.jpg). New optional deletion field deployment and private runtime sync acceptance pending |
| Minimum OS | iOS 17 |
| Languages | Arabic and English |
| Privacy-policy URL | `[ACTUAL_PUBLIC_PRIVACY_URL]` |
| Support URL | `[ACTUAL_PUBLIC_SUPPORT_URL]` |
| Copyright | `[YEAR] [LEGAL_OPERATOR_NAME]` |

The price has already been set in App Store Connect; it is not hard-coded in the app or marketing description. Read-only Business verification confirmed that the Paid Apps Agreement is already Active, as required for paid public sale. The Brazil tax form still shows missing information and needs owner review for applicable distribution requirements before public sale. No agreement was accepted or tax form changed during the agent-run verification. These account checks do not authorize public release or establish device/iCloud acceptance. [Apple pricing guidance](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/), [Apple agreement requirements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements).

## العربية

**الاسم:** شيكاتي

**العنوان الفرعي:** شيكاتك ومواعيدها في مكان واحد

**النص الترويجي:** تابع شيكاتك الواردة والصادرة، ورتّب مواعيدها، واستعد للاستحقاق بتذكيرات واضحة. إدخال سريع، صور للشيكات، وواجهة سهلة بالعربية والإنجليزية.

**الوصف:**

شيكاتي يساعدك على تنظيم الشيكات الواردة والصادرة ومتابعة مواعيد استحقاقها وتاريخ تحصيلها أو صرفها الفعلي، من مكان واحد على الآيفون.

أضف مبلغ الشيك وتاريخ الاستحقاق، ثم أكمل رقم الشيك والبنك والفرع وصاحب الشيك أو المستفيد ومرجع الحساب والملاحظات عند الحاجة. صوّر الشيك أو أرفق صورته لاقتراح المعلومات القابلة للقراءة على جهازك، وراجعها قبل الحفظ.

• ملخص للوارد والصادر غير المسدّد وشيكات اليوم والقريبة والمتأخرة.
• بحث وتصنيف وترتيب حسب التاريخ والمبلغ والاسم والحالة، أو ترتيب يدوي بالسحب.
• حالات واضحة للمعلّق والمرتجع والملغى، وتأكيد التحصيل أو الصرف بتاريخ فعلي.
• تذكيرات قابلة للتعديل قبل الاستحقاق وفي يومه، وملخص يومي اختياري.
• عرض فترة تغطية التنبيهات وتذكير لفتح التطبيق وتجديد جدولتها عند الحاجة.
• حفظ محلي يعمل دون إنترنت، ومزامنة خاصة عبر iCloud عند توفرها.
• قفل اختياري باستخدام مصادقة الجهاز، وإمكانية إخفاء تفاصيل التنبيهات.
• لغة عربية وإنجليزية، ووضع فاتح وداكن، ودعم تكبير الخط.
• حفظ وإضافة متتابعة، واقتراح أسماء وبنوك سابقة، وتنبيه عند احتمال تكرار الشيك.
• عرض غير المسدّدة أو السجل الكامل، مع اختصارات اليوم والأسبوع والمتأخرة.
• استعادة الشيكات المحذوفة خلال 30 يومًا، ونسخ احتياطية مشفّرة بكلمة مرور تشمل الصور.
• استيراد CSV بعد مراجعة الأخطاء والتكرار، وتصدير CSV قابل للفتح في Excel وكشف PDF للشيكات الظاهرة.
• معرفة أقرب تذكير مجدول للشيك وتأجيل التذكير ساعة من الإشعار.

تختار عملة واحدة لسجلاتك. تتطلب التنبيهات إذنًا من إعدادات الآيفون، وقد تتأثر بوضع التركيز وإعدادات النظام. قراءة الصور تقدم اقتراحات تحتاج إلى مراجعتك. الشراء مرة واحدة، وجميع الميزات مشمولة.

**الكلمات المفتاحية:** شيك,شيكات,استحقاق,صرف,تحصيل,تذكير,بنك,مواعيد,مال,تنظيم

**ما الجديد في الإصدار الأول:** إدخال متتابع، وتأكيد الصرف بتاريخ فعلي، وعرض غير المسدّدة والسجل، ومراجعة التكرار، واستعادة خلال 30 يومًا، ونسخ احتياطي مشفّر، وتقارير CSV وPDF، وتذكيرات الاستحقاق بالعربية والإنجليزية.

## English

**Name:** Shekati

**Subtitle:** Cheques, dates and reminders

**Promotional text:** Organize incoming and outgoing cheques, track due dates, and prepare with clear reminders. Quick entry, cheque photos, and an easy Arabic and English interface.

**Description:**

Shekati keeps your incoming and outgoing cheques, due dates, and actual collection or payment dates together on your iPhone.

Start with an amount and due date. Add the cheque number, bank, branch, payer or beneficiary, account reference, and notes when needed. Photograph a cheque or attach an image to receive on-device suggestions for readable details, then review them before saving.

• See outstanding incoming and outgoing totals, cheques due today, upcoming cheques, and overdue cheques.
• Search, filter, and sort by date, amount, name or status, or drag to arrange cheques manually.
• Track pending, returned, cancelled and settled cheques, recording the actual collection or payment date.
• Customize reminders before the due date and on the day, with an optional daily summary.
• View notification coverage and receive a reminder to reopen the app when the schedule needs refreshing.
• Keep records locally while offline, with private iCloud sync when available.
• Enable device authentication and hide notification details for extra privacy.
• Use Arabic or English, light or dark appearance, and larger text.
• Save and add the next cheque, reuse previous names and banks, and review possible duplicates.
• Switch between outstanding cheques and full history, with today, week and overdue shortcuts.
• Restore deleted cheques within 30 days and create password-encrypted backups including photos.
• Preview CSV import errors and duplicates, export Excel-compatible CSV, and save a filtered PDF report.
• See a cheque's next accepted reminder and snooze a notification for one hour.

Choose one currency for your records. Reminders require notification permission and can be affected by Focus and system settings. Image reading supplies suggestions for you to review. One purchase includes every feature.

**Keywords:** cheque,check,due,date,reminder,payment,bank,finance,organizer,tracker

**What's new:** First release with consecutive cheque entry, actual-date settlement, outstanding/history views, duplicate review, 30-day recovery, encrypted backup, CSV/PDF reports and due-date reminders in Arabic and English.

## Review notes

No app-specific sign-in is required. An Apple Account with iCloud is needed for private sync, but local records remain usable without it. Device authentication is optional and off by default. No in-app purchase or subscription is offered; this is a paid-download app.

To test: choose a currency, add an incoming or outgoing cheque with amount and due date, save, inspect the dashboard and list, and confirm settlement with an actual date. Allow notifications when requested. Enable the optional app lock in Settings. Camera/image recognition suggests fields and always requires review before saving. A due date passing does not mark a cheque as paid.

The notification schedule is bounded to 60 requests; Settings exposes actual coverage and any scheduling errors. The app replenishes when opened, records/settings change, or sync imports change records. The replenishment notification is not a background scheduler.

The eight enhancements are described in [ENHANCEMENTS.md](ENHANCEMENTS.md). For recovery testing, delete a fictional cheque and restore it from Settings → Recently deleted. Data and backup provides password-encrypted file creation/restoration and CSV preview. PDF and CSV exports use the visible filtered rows. Backup passwords must be at least ten characters and are not recoverable; CSV omits images. Snooze requires device authentication and shares the bounded queue.

Provide `[REAL_REVIEW_CONTACT_NAME]`, `[REAL_REVIEW_CONTACT_EMAIL]` and `[REAL_REVIEW_CONTACT_PHONE]` in App Store Connect. Do not submit these placeholders.

## Screenshot brief

Capture actual iPhone screens in each language: dashboard, searchable cheque list, add-cheque form, cheque details with a fictional sample image, and reminder/privacy settings. Use fictional account names and numbers. Include a dark-mode example and demonstrate readable enlarged text. Do not use customer bank data. Check Apple's current upload dimensions when preparing final screenshots.

Verified raw native **build 6** iPhone Air simulator captures (1260×2736), from the complete passing suite:

- Arabic: [Home](screenshots/native-build6-arabic-home.png), [table](screenshots/native-build6-arabic-table.png), [entry](screenshots/native-build6-arabic-entry.png), [quick periods](screenshots/native-build6-arabic-quick-periods.png) and [data tools](screenshots/native-build6-arabic-data-tools.png).
- English: [entry](screenshots/native-build6-english-entry.png), [table](screenshots/native-build6-english-table.png), [next cheque date review](screenshots/native-build6-english-consecutive-date-review.png), [duplicate warning](screenshots/native-build6-english-duplicate-warning.png), [actual payment date](screenshots/native-build6-english-payment-date.png) and [Recently deleted](screenshots/native-build6-english-recently-deleted.png).
- Accessibility: [large-text layout](screenshots/native-build6-large-text.png). All 23 original PNGs and their passing tests/hashes are listed in the [provenance manifest](NATIVE_BUILD6_SCREENSHOTS.json).

These are raw simulator captures with fictional records. Complete final store presentation, dark-mode captures and physical-device acceptance before public submission. Historical build-5 captures remain in the project and [validation history](VALIDATION.md).
