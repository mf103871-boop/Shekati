# شيكاتي | Shekati

تطبيق أصلي للآيفون لمتابعة الشيكات الواردة والصادرة، بواجهة بسيطة بالعربية والإنجليزية. الرئيسية تعرض إجمالي الشيكات غير المسوّاة وروابط المستحق اليوم وخلال أسبوع والمتأخر؛ القائمة تعرض الاسم والرقم والمبلغ والتاريخ بوضوح. إدخال سريع للمعلومات الأساسية، مع تفاصيل البنك والصور والتذكيرات القابلة للتوسيع. يدعم النص الكبير، والحفظ المحلي دون اتصال، والمزامنة الخاصة عبر iCloud. الحد الأدنى iOS 17.

An iPhone-only SwiftUI app for cheque tracking. The simplified interface uses flat incoming/outgoing outstanding totals, date-list links, a compact cheque table, direction filters and visible count/amount summaries. Essential entry fields appear first; bank details, images and reminder options expand when needed. Arabic RTL, English LTR and labelled large-text layouts are included.

The [interface simplification notes](docs/UI_SIMPLIFICATION.md) record the cheque-only scope and acceptance criteria.

Current source is **1.0.0 (5)** at [8f806ae](https://github.com/mf103871-boop/Shekati/commit/8f806ae2a3d370dcab6c1cc7597c9d4a8d503ce6). Its [build pipeline 37164184467](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467) passed native validation and signed iPhone-only archive/export/upload. Build 5 is available in the internal TestFlight group with status `Testing`; [portal proof](docs/screenshots/Shekati-TestFlight-build5.jpg). App Store Connect now reports `Installed 1.0.0 (5)` on the owner's iPhone. That portal report does not confirm physical UI, private-iCloud sync or device-notification acceptance; these remain pending. See [account and beta status](docs/ACCOUNT_SETUP_STATUS.md) for current evidence.

## What is included

- Incoming/outgoing cheques, due dates and actual settlement dates. Pending and returned cheques remain outstanding; settled entries show Collected or Paid.
- Quick manual entry, expandable optional details, front/back attachments and on-device Vision suggestions reviewed before saving.
- Search, combined filters, persistent ascending/descending sorts and manual order preserving hidden rows.
- One chosen currency, exact minor-unit amounts and civil dates. Currency conflicts hide combined totals.
- Local reminders by default at 09:00, three days and one day before due date and on due date; per-cheque days/time and an optional daily summary.
- A bounded 60-request notification queue, visible coverage status, replenishment reminders and live civil-day refresh.
- SwiftData local storage, offline entry and private iCloud synchronization without a custom account server.
- Optional device authentication, covered app-switcher previews and hidden notification details.
- Core tests, iPhone unit/integration and UI tests, plus hosted macOS validation and a manually invoked TestFlight upload workflow.

The commercial model is a **$9.99 paid download**, with all features included and no subscription or in-app purchase. The US base price is [saved in App Store Connect](docs/screenshots/Shekati-price-saved.jpg). Mac and Apple Vision Pro availability are disabled; the reduced school-volume price is unchecked. Pricing is store configuration; the app has not been publicly released.

## Build and release

Use the [build guide](docs/BUILD.md) for XcodeGen, macOS or Windows with hosted macOS, Apple signing, private iCloud setup and TestFlight secrets. The [device acceptance checklist](docs/DEVICE_QA.md) covers the simplified interface, physical iCloud transfers, reminders, camera and privacy checks. Build 5 is ready for internal testing; recorded physical-device acceptance is still required.

حالة الحسابات والربط والتوزيع موثّقة في [حالة التجهيز الفعلية](docs/ACCOUNT_SETUP_STATUS.md)، وخطوات المتابعة من ويندوز في [دليل ربط الحسابات](docs/CONNECT_ACCOUNTS_AR.md). نشر مخطط iCloud إلى الإنتاج مكتمل؛ اختبار المزامنة والتنبيهات على الهاتف ما زال مطلوبًا.

Release material is supplied in [Arabic and English store copy](docs/APP_STORE.md), [privacy-policy draft](docs/PRIVACY.md) and [support-page draft](docs/SUPPORT.md). Actual public privacy/support URLs, operator contact details and the remaining store requirements must be completed before App Review.

## معاينة التصميم | Design preview

افتح [المعاينة التفاعلية](Preview/index.html) لتجربة الشاشات والإدخال والبحث ببيانات تجريبية. بياناتها مؤقتة وتُعاد عند تحديث الصفحة؛ الكاميرا والتنبيهات وiCloud والقفل تحتاج اختبار التطبيق الأصلي على iOS.

The browser preview supplements design review. It is not an installable app, a native test result or an App Store screenshot. The actual app starts with an empty store and currency setup. Current native build 5 captures include the [Arabic cheque table](docs/screenshots/native-build5-arabic-table.png), [quick entry](docs/screenshots/native-build5-arabic-entry.png) and [large-text layout](docs/screenshots/native-build5-large-text.png); the complete set is linked in [store material](docs/APP_STORE.md).

## Validation status

Build 5 passed the separate **24-test macOS core suite** and **58 distinct iPhone tests** (24 core, 30 hosted and 4 UI), with zero failures in the [native validation job](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467/job/111323630876). The [signed upload job](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467/job/111324443434) also passed archive, export and upload, including the iPhone-only family `[1]` guards; [upload proof](docs/screenshots/Shekati-build5-upload-success.jpg). Nine raw iPhone Air simulator screenshots document the simplified interface.

See [validation results](docs/VALIDATION.md) for current checks and historical build evidence, and [account status](docs/ACCOUNT_SETUP_STATUS.md) for verified store/setup stages. Simulator builds use local-only storage. Production schema deployment is complete, but signed-phone private export/import, cross-device transfers and device notifications still require recorded acceptance results.

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
