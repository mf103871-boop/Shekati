# شيكاتي | Shekati

تطبيق أصلي للآيفون لمتابعة الشيكات الواردة والصادرة، وتواريخ الاستحقاق والصرف الفعلي، والصور والتذكيرات. واجهة عربية وإنجليزية، حفظ محلي، ومزامنة خاصة عبر iCloud. الحد الأدنى iOS 17.

This repository contains the SwiftUI app, its SwiftData models, a Foundation-only business-logic package, automated tests, XcodeGen configuration, and hosted macOS build workflows. [Version 1.0.0, build 2](https://appstoreconnect.apple.com/teams/609ff8f7-15ce-48ec-9e60-e95f8ed24d3a/apps/6818852973/testflight/ios/c6a99453-40c5-4cd3-a86b-aeca16550426) is confirmed `Ready to Test` in the internal TestFlight group's Builds tab, with `Expires in 90 days`. Native tests, visual review and signed upload passed. One owner tester was invited on 3 October 2026; invitation acceptance and installation of the regular TestFlight app are not confirmed.

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

تم ربط المستودع الخاص وهوية التطبيق وحاوية iCloud وسجل المتجر، وإصدار شهادة وملف التوزيع وحفظ الأسرار الثمانية في بيئة GitHub المقيّدة بفرع `main`. البناء رقم 2 جاهز للاختبار في TestFlight ومربوط بمجموعة اختبار المالك، التي تضم مختبرًا واحدًا وبناءً واحدًا. أُرسلت دعوة المالك في 3 أكتوبر 2026 وتظهر الحالة `Invited`؛ قبولها وتثبيت النسخة العادية عبر TestFlight لم يُؤكَّدا بعد. في 4 أكتوبر سُجّل هاتف المالك، وثُبّتت نسخة **Shekati Sync Setup** رقم 3، وأكدت صورة الهاتف اكتمال التهيئة في بيئة التطوير. روجع المخطط ونُشر إلى الإنتاج، ثم تأكد تطابق جميع الحقول وفهارسها بين البيئتين؛ [دليل نشر iCloud](docs/screenshots/Shekati-iCloud-production-schema.jpg). الخطوة المتبقية هي تثبيت شيكاتي العادي من TestFlight واختبار المزامنة على الجهاز. راجع [حالة الربط الفعلية](docs/ACCOUNT_SETUP_STATUS.md) و[متابعة التجهيز من ويندوز](docs/CONNECT_ACCOUNTS_AR.md).

## معاينة التصميم | Design preview

افتح [المعاينة التفاعلية](Preview/index.html) لاستعراض الألوان والشاشات بالعربية والإنجليزية، وتجربة إدخال بيانات تجريبية والبحث والحذف. المعاينة مستقلة عن تطبيق الآيفون؛ بياناتها مؤقتة وتُعاد عند تحديث الصفحة. الكاميرا والتنبيهات وiCloud والقفل موجودة في المصدر الأصلي، وتحتاج اختبار iOS فعليًا.

The local preview is supplementary design review, not an installable app, native test result, or App Store screenshot. The actual app starts with an empty store and currency setup.

Release material is supplied in [Arabic and English store copy](docs/APP_STORE.md), [privacy-policy draft](docs/PRIVACY.md), and [support-page draft](docs/SUPPORT.md). Operator contact details and actual public privacy/support URLs must be filled in before submission.

## Validation status

Build 2's complete native [validation job 111274269760](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274269760) passed using Xcode 26.6 and an iOS 26.5 simulator: all 24 macOS core tests, then all 48 iPhone scenarios (24 core, 22 hosted unit/integration and both UI tests). The separate native [cloud schema bootstrap tool](Tools/SchemaBootstrap/README.md) also built successfully. Fresh native screenshots confirmed readable English Settings with the correct left-to-right layout after switching from Arabic, with the selected Settings tab preserved.

Build 2's [signed upload job 111274911754](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274911754) succeeded, including both archive and IPA checks for the iPhone-only device family `[1]`; [saved success proof](docs/screenshots/Shekati-build-upload-success.jpg). The earlier build 1 rejection (90474, unintended iPad support) is resolved in the signed output. The [TestFlight group proof](docs/screenshots/Shekati-TestFlight-build.jpg) confirms build 2 is attached to `Shekati Owner Testing` and `Ready to Test`. The owner invitation was sent. The registered-phone setup completed and its CloudKit schema was deployed to Production on 4 October 2026: all 40 cheque fields and 7 configuration fields, plus 6 metadata fields per type, and 75 generated indexes were verified against Development. Regular TestFlight installation and signed-device private export/import remain unverified.

These native test results apply to build 2 commit [7325d7046101](https://github.com/mf103871-boop/Shekati/commit/7325d70461017efe53bec6e44b1d59c54d72220e). Read-only account verification confirmed the Paid Apps Agreement is already active. The Brazil tax form still shows missing information; publication URLs/contact details and public App Review remain outstanding. The internal group `Shekati Owner Testing` has one attached build and one owner tester, with automatic distribution off. The tester's status is `Invited`; installation or a session of the regular TestFlight build has not been confirmed. The temporary schema app's installation and successful initialization are confirmed separately.

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
