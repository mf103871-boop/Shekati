# شيكاتي | Shekati

تطبيق أصلي للآيفون لمتابعة الشيكات الواردة والصادرة، بواجهة بسيطة بالعربية والإنجليزية. الرئيسية تعرض إجمالي الشيكات غير المسوّاة وروابط المستحق اليوم وخلال أسبوع والمتأخر؛ القائمة تعرض الاسم والرقم والمبلغ والتاريخ بوضوح. إدخال سريع للمعلومات الأساسية، مع تفاصيل البنك والصور والتذكيرات القابلة للتوسيع. يدعم النص الكبير، والحفظ المحلي دون اتصال، والمزامنة الخاصة عبر iCloud. الحد الأدنى iOS 17.

An iPhone-only SwiftUI app for cheque tracking. The simplified interface uses flat incoming/outgoing outstanding totals, date-list links, a compact cheque table, direction filters and visible count/amount summaries. Essential entry fields appear first; bank details, images and reminder options expand when needed. Arabic RTL, English LTR and labelled large-text layouts are included.

The [interface simplification notes](docs/UI_SIMPLIFICATION.md) record the cheque-only scope and acceptance criteria. The eight requested additions are implemented and explained in [enhancement and recovery guidance](docs/ENHANCEMENTS.md): consecutive entry, explicit settlement, saved outstanding/history views, separate totals and duplicate warnings, recently deleted records, encrypted backup, CSV/PDF transfer, and verified reminder coverage with snooze.

**1.0.0 (6)** at [source 7c5c1a9c](https://github.com/mf103871-boop/Shekati/commit/7c5c1a9c68b4a001fec2a51e8bf198c538089d57) passed all 113 distinct iPhone scenarios and the separate 29-case macOS core suite in the [complete native/signing/upload pipeline](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531). Signed upload completed at 03:26:42 UTC on 4 October. Apple confirmed processing state `VALID` through its authenticated API at 03:33:14 UTC; build 6 installation remains unverified and browser sign-in is required for Console work; the additive iCloud deletion field must be deployed before owner-group assignment. Build 5 remains the last available owner beta. See [account status](docs/ACCOUNT_SETUP_STATUS.md) and [validation evidence](docs/VALIDATION.md).

## What is included

- Incoming/outgoing cheques, due dates and actual settlement dates. Pending and returned cheques remain outstanding; settled entries show Collected or Paid.
- Quick manual entry, expandable optional details, front/back attachments and on-device Vision suggestions reviewed before saving.
- Consecutive entry with optional retained details, keyboard navigation, previous-name/bank suggestions and a duplicate review before deliberate repeated entry.
- Search, combined filters, persistent ascending/descending sorts and manual order preserving hidden rows.
- Saved outstanding/history scope, relative due dates, date shortcuts and separate incoming/outgoing totals of the visible rows.
- One chosen currency, exact minor-unit amounts and civil dates. Currency conflicts hide combined totals.
- Local reminders by default at 09:00, three days and one day before due date and on due date; per-cheque days/time and an optional daily summary.
- A bounded 60-request notification queue, visible coverage status, replenishment reminders and live civil-day refresh.
- Actual accepted next-reminder dates, preserved valid unanswered alerts and authenticated one-hour snooze within the same queue.
- SwiftData local storage, offline entry and private iCloud synchronization without a custom account server.
- Recently deleted records with undo and 30-day restoration, password-encrypted full backups, reviewed CSV imports/exports and filtered multi-page Arabic/English PDF reports.
- Optional device authentication, covered app-switcher previews and hidden notification details.
- Core tests, iPhone unit/integration and UI tests, plus hosted macOS validation and a manually invoked TestFlight upload workflow.

The commercial model is a **$9.99 paid download**, with all features included and no subscription or in-app purchase. The US base price is [saved in App Store Connect](docs/screenshots/Shekati-price-saved.jpg). Mac and Apple Vision Pro availability are disabled; the reduced school-volume price is unchecked. Pricing is store configuration; the app has not been publicly released.

## Build and release

Use the [build guide](docs/BUILD.md) for XcodeGen, macOS or Windows with hosted macOS, Apple signing, private iCloud setup and TestFlight secrets. The [device acceptance checklist](docs/DEVICE_QA.md) covers the enhanced interface, recovery, physical iCloud transfers, reminders, camera and privacy checks. Recorded physical-device acceptance is still required.

حالة الحسابات والربط والتوزيع موثّقة في [حالة التجهيز الفعلية](docs/ACCOUNT_SETUP_STATUS.md)، وخطوات المتابعة من ويندوز في [دليل ربط الحسابات](docs/CONNECT_ACCOUNTS_AR.md). مخطط النسخة السابقة منشور؛ يحتاج حقل الحذف الجديد إلى تحديث الإنتاج قبل توزيع النسخة الجديدة. اختبار المزامنة والتنبيهات على الهاتف ما زال مطلوبًا.

Release material is supplied in [Arabic and English store copy](docs/APP_STORE.md), [privacy-policy draft](docs/PRIVACY.md) and [support-page draft](docs/SUPPORT.md). Actual public privacy/support URLs, operator contact details and the remaining store requirements must be completed before App Review.

## معاينة التصميم | Design preview

افتح [المعاينة التفاعلية](Preview/index.html) لتجربة الشاشات والإدخال والبحث ببيانات تجريبية. بياناتها مؤقتة وتُعاد عند تحديث الصفحة؛ الكاميرا والتنبيهات وiCloud والقفل تحتاج اختبار التطبيق الأصلي على iOS.

The browser preview shows the earlier simplified design. It is not an installable app, a native test result or an App Store screenshot, and it does not exercise the new recovery/report features. The actual app starts with an empty store and currency setup. Historical native build 5 captures include the [Arabic cheque table](docs/screenshots/native-build5-arabic-table.png), [quick entry](docs/screenshots/native-build5-arabic-entry.png) and [large-text layout](docs/screenshots/native-build5-large-text.png); the complete set is linked in [store material](docs/APP_STORE.md).

## Validation status

All 113 distinct iPhone scenarios passed, including consecutive entry, duplicate review, actual-date settlement, recovery, backup validation, Arabic/English and large text. The separate 29-case macOS core run also passed. [Validation results](docs/VALIDATION.md) record exact source, jobs, artifacts and limits. All 23 final raw screenshots passed visual review; see the [Arabic cheque table](docs/screenshots/native-build6-arabic-table.png), [data tools](docs/screenshots/native-build6-arabic-data-tools.png) and [provenance manifest](docs/NATIVE_BUILD6_SCREENSHOTS.json).

See [validation results](docs/VALIDATION.md) for current checks and historical build evidence, and [account status](docs/ACCOUNT_SETUP_STATUS.md) for verified store/setup stages. Simulator builds use local-only storage. The new optional deletion field needs Production deployment; signed-phone private export/import, cross-device transfers and device notifications still require recorded acceptance results.

## Structure

| Area | Purpose |
| --- | --- |
| `Shekati/` | SwiftUI app, SwiftData persistence, device services and localized resources |
| `Packages/ShekatiCore/` | Exact money/date handling, cheque filtering, ordering and dashboard logic |
| `ShekatiTests/` | iPhone unit/integration coverage of persistence, reminders and sync status |
| `ShekatiUITests/` | Isolated XCUITest coverage of entry, language, direction filters and large text |
| `project.yml` | Reproducible Xcode project definition |
| `.github/workflows/` | Unsigned CI checks and manually requested signed TestFlight upload |
| `docs/` | Build guide, device QA, validation evidence and bilingual release drafts |
| `Preview/` | Interactive design preview with fictional data |
| `Tools/SchemaBootstrap/` | Development-only native tool for initializing the CloudKit schema before deployment |

No user financial records, Apple credentials, generated project, archives or signing files are included.
