# شيكاتي | Shekati

تطبيق أصلي للآيفون لمتابعة الشيكات الواردة والصادرة، وتواريخ الاستحقاق والصرف الفعلي، والصور والتذكيرات. واجهة عربية وإنجليزية، حفظ محلي، ومزامنة خاصة عبر iCloud. الحد الأدنى iOS 17.

This repository contains the SwiftUI app, its SwiftData models, a Foundation-only business-logic package, automated tests, XcodeGen configuration, and hosted macOS build workflows. [Version 1.0.0, build 4](https://appstoreconnect.apple.com/teams/609ff8f7-15ce-48ec-9e60-e95f8ed24d3a/apps/6818852973/testflight/ios/6dede7f6-d343-417f-90f2-9faf43325da6) is attached to the owner internal TestFlight group and confirmed `Testing`, with `Expires in 90 days`; [portal proof](docs/screenshots/Shekati-TestFlight-build4.jpg). The group has one tester and two builds. App Store Connect reports the owner installed regular build 2 on 4 October 2026. Installation of build 4 and private-sync/device acceptance remain unverified.

The latest source correction is build **1.0.0 (4)** at commit [558db5efcb24](https://github.com/mf103871-boop/Shekati/commit/558db5efcb24d0acf11a0f82ea7da1fc72b10f6c). It preserves unresolved sync failures during account checks and reconnection. All **56 iPhone scenarios** and the separate 24-test macOS core suite passed in [run 37161293969](https://github.com/mf103871-boop/Shekati/actions/runs/37161293969), followed by signed iPhone-only archive/export and an error-free upload; [success proof](docs/screenshots/Shekati-build4-upload-success.jpg). Processing completed, and internal availability is confirmed separately in the group Builds tab.

## What is included

- Dashboard totals and due-today, next-seven-day, and overdue lists.
- Manual entry, front/back attachments, and on-device Vision suggestions that users review before saving.
- Search, combined filters, persistent sorting, and manual order preserving hidden rows.
- Exact currency minor units and civil dates; returned cheques remain outstanding until resolved.
- Local reminders at 9:00 AM, three days and one day before due date and on due date; optional daily summary.
- A bounded 60-request notification queue, explicit coverage status, and a replenishment reminder.
- Optional device authentication, hidden app-switcher preview, and notification privacy controls.
- Per-cheque reminder days and time, with inherited defaults and live civil-day refresh.
- Core unit tests, iPhone integration tests and an isolated XCUITest flow, plus a manually invoked TestFlight upload workflow.

The commercial model is a **$9.99 paid download**, with all features included and no subscription or in-app purchase. The US base price has been [saved in App Store Connect](docs/screenshots/Shekati-price-saved.jpg). Mac and Apple Vision Pro availability and the reduced school volume price were unchecked and saved. Pricing is a store configuration; the app has not been publicly released.

## Build and release

See [Build guide](docs/BUILD.md) for macOS or Windows-with-hosted-macOS instructions, Apple signing, private iCloud setup, and TestFlight secrets. Build 2 automated simulator validation has passed; [real-device acceptance checks](docs/DEVICE_QA.md) remain pending.

تم ربط المستودع الخاص وهوية التطبيق وحاوية iCloud وسجل المتجر، وإصدار شهادة وملف التوزيع وحفظ الأسرار الثمانية في بيئة GitHub المقيّدة بفرع `main`. البناء رقم 4 متاح الآن في TestFlight بحالة `Testing`، ومجموعة المالك تضم مختبرًا واحدًا وبناءين. بعد الدعوة المرسلة في 3 أكتوبر، أظهرت بوابة Apple تثبيت النسخة العادية رقم 2 على هاتف المالك في 4 أكتوبر. في اليوم نفسه اكتملت تهيئة **Shekati Sync Setup** رقم 3 ونشر مخطط iCloud إلى الإنتاج، وتأكد تطابق جميع الحقول وفهارسها؛ [دليل النشر](docs/screenshots/Shekati-iCloud-production-schema.jpg). نجحت اختبارات النسخة الرابعة الـ56 وأرشفتها ورفعها. التحديث إليها واختبار المزامنة الفعلية على الجهاز ما زالا بانتظار النتيجة. راجع [حالة الربط الفعلية](docs/ACCOUNT_SETUP_STATUS.md) و[متابعة التجهيز من ويندوز](docs/CONNECT_ACCOUNTS_AR.md).

## معاينة التصميم | Design preview

افتح [المعاينة التفاعلية](Preview/index.html) لاستعراض الألوان والشاشات بالعربية والإنجليزية، وتجربة إدخال بيانات تجريبية والبحث والحذف. المعاينة مستقلة عن تطبيق الآيفون؛ بياناتها مؤقتة وتُعاد عند تحديث الصفحة. الكاميرا والتنبيهات وiCloud والقفل موجودة في المصدر الأصلي، وتحتاج اختبار iOS فعليًا.

The local preview is supplementary design review, not an installable app, native test result, or App Store screenshot. The actual app starts with an empty store and currency setup.

Release material is supplied in [Arabic and English store copy](docs/APP_STORE.md), [privacy-policy draft](docs/PRIVACY.md), and [support-page draft](docs/SUPPORT.md). Operator contact details and actual public privacy/support URLs must be filled in before submission.

## Validation status

Build 2's complete native [validation job 111274269760](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274269760) passed using Xcode 26.6 and an iOS 26.5 simulator: all 24 macOS core tests, then all 48 iPhone scenarios (24 core, 22 hosted unit/integration and both UI tests). The separate native [cloud schema bootstrap tool](Tools/SchemaBootstrap/README.md) also built successfully. Fresh native screenshots confirmed readable English Settings with the correct left-to-right layout after switching from Arabic, with the selected Settings tab preserved.

Build 2's [signed upload job 111274911754](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274911754) succeeded, including both archive and IPA checks for the iPhone-only device family `[1]`; [saved success proof](docs/screenshots/Shekati-build-upload-success.jpg). The earlier build 1 rejection (90474, unintended iPad support) is resolved in the signed output. The earlier [TestFlight group proof](docs/screenshots/Shekati-TestFlight-build.jpg) confirms build 2 was attached and `Ready to Test`; the current group includes build 4 and shows both as `Testing`. The registered-phone setup completed and its CloudKit schema was deployed to Production on 4 October 2026: all 40 cheque fields and 7 configuration fields, plus 6 metadata fields per type, and 75 generated indexes were verified against Development. App Store Connect reports regular build 2 installed. Updating to build 4 and signed-device private export/import acceptance remain unverified.

These historical native test results apply to build 2 commit [7325d7046101](https://github.com/mf103871-boop/Shekati/commit/7325d70461017efe53bec6e44b1d59c54d72220e); build 4's renewed results are recorded above. Read-only account verification confirmed the Paid Apps Agreement is already active. The Brazil tax form still shows missing information; publication URLs/contact details and public App Review remain outstanding. The internal group `Shekati Owner Testing` now has two attached builds and one owner tester, with automatic distribution off. The tester row reports `Installed 1.0.0 (2)` on the intended iPhone; no runtime/private-sync acceptance result is claimed. The temporary schema app's installation and successful initialization are confirmed separately.

Actual build 2 simulator captures: [Arabic Home](docs/screenshots/native-arabic-home.png), [English cheque detail](docs/screenshots/native-english-detail.png), and [English Settings after language change](docs/screenshots/native-english-settings.png). These are raw native captures, separate from the browser design preview.

See [validation results](docs/VALIDATION.md) for the checks actually performed and checks still pending. Simulator builds intentionally use local-only storage; private iCloud must be tested with a signed iPhone build.

## Structure

| Area | Purpose |
| --- | --- |
| `Shekati/` | SwiftUI app, persistence, device services and localized resources |
| `Packages/ShekatiCore/` | Exact money/date handling, cheque filtering, ordering and dashboard logic |
| `ShekatiTests/` | iPhone XCTest coverage of reminders and persistence |
| `ShekatiUITests/` | XCUITest app-entry flow using an isolated in-memory test launch |
| `project.yml` | Reproducible Xcode project definition |
| `.github/workflows/` | Unsigned CI checks and manually requested signed TestFlight upload |
| `docs/` | Build guide, device QA and bilingual release drafts |
| `Preview/` | Interactive design preview with fictional data and preview screenshots |
| `Tools/SchemaBootstrap/` | Development-only native tool for initializing the CloudKit schema before deployment |

No user financial records, Apple credentials, generated project, archives or signing files are included.
