# شيكاتي | Shekati

تطبيق أصلي للآيفون لمتابعة الشيكات الواردة والصادرة، وتواريخ الاستحقاق والصرف الفعلي، والصور والتذكيرات. واجهة عربية وإنجليزية، حفظ محلي، ومزامنة خاصة عبر iCloud. الحد الأدنى iOS 17.

This repository contains the SwiftUI app, its SwiftData models, a Foundation-only business-logic package, automated tests, XcodeGen configuration, and hosted macOS build workflows. The native app has compiled on hosted macOS; an installable iPhone build is still pending signing and TestFlight upload.

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

The commercial model is a **$9.99 paid download**, with all features included and no subscription or in-app purchase. App Store pricing is configured in App Store Connect; it is not an application setting.

## Build and release

See [Build guide](docs/BUILD.md) for macOS or Windows-with-hosted-macOS instructions, Apple signing, private iCloud setup, and TestFlight secrets. Start with an unsigned simulator CI build, then perform [real-device acceptance checks](docs/DEVICE_QA.md).

تم ربط المستودع الخاص وهوية التطبيق وحاوية iCloud وسجل المتجر، وإصدار شهادة وملف التوزيع وحفظ أسرار التوقيع والنشر السبعة في بيئة GitHub المقيّدة بفرع `main`. تهيئة مخطط iCloud ورفع TestFlight قيد التجهيز. راجع [حالة الربط الفعلية](docs/ACCOUNT_SETUP_STATUS.md) و[متابعة التجهيز من ويندوز](docs/CONNECT_ACCOUNTS_AR.md).

## معاينة التصميم | Design preview

افتح [المعاينة التفاعلية](Preview/index.html) لاستعراض الألوان والشاشات بالعربية والإنجليزية، وتجربة إدخال بيانات تجريبية والبحث والحذف. المعاينة مستقلة عن تطبيق الآيفون؛ بياناتها مؤقتة وتُعاد عند تحديث الصفحة. الكاميرا والتنبيهات وiCloud والقفل موجودة في المصدر الأصلي، وتحتاج اختبار iOS فعليًا.

The local preview is supplementary design review, not an installable app, native test result, or App Store screenshot. The actual app starts with an empty store and currency setup.

Release material is supplied in [Arabic and English store copy](docs/APP_STORE.md), [privacy-policy draft](docs/PRIVACY.md), and [support-page draft](docs/SUPPORT.md). Operator contact details and actual public privacy/support URLs must be filled in before submission.

## Validation status

Hosted macOS [run 37145564552](https://github.com/mf103871-boop/Shekati/actions/runs/37145564552) compiled the native app using Xcode 26.6 and an iOS 26.5 simulator. All 24 core tests, all 22 hosted unit/integration tests, and the Arabic-to-English UI test passed. The add-cheque UI test failed when the test harness could not reach an offscreen field. [Retry 37146039264](https://github.com/mf103871-boop/Shekati/actions/runs/37146039264) repeated those passes but still failed to reach the party field; its simulator result is under review. Complete validation has not passed yet.

No TestFlight build has been uploaded. Private iCloud sync, camera, biometrics and closed-app notification delivery still require signed physical-iPhone checks.

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

No user financial records, Apple credentials, generated project, archives or signing files are included.
