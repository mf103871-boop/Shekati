# حالة التحقق | Validation status

Prepared on 3 October 2026 in a Windows workspace. The following distinguishes checks actually executed from native tests written for the macOS pipeline.

| Check | Result |
| --- | --- |
| 34 Swift source files parsed with the Swift tree-sitter grammar | Passed syntax parsing; this is not compilation or API/type checking |
| XcodeGen and both GitHub workflow YAML files | Parsed successfully |
| Five embedded workflow Python snippets | Syntax parsed successfully |
| Info, entitlement and privacy plist structures | Parsed successfully |
| Asset catalog JSON and opaque 1024×1024 RGB app icon | Validated |
| Arabic dictionary and direct localization calls | 243 keys, no duplicate keys or missing direct literal translations |
| Interactive preview | Add, amount validation, leading-zero search, filters, settlement, delete/cancel, language, theme and summary controls passed |
| Preview layout | Arabic and English visually inspected; 375px and 320px layouts have no horizontal overflow |
| JavaScript runtime in preview | No page errors during checks |
| Native Swift compilation and XCTest execution | Not run; requires macOS/Xcode |
| Signed device camera, Vision accuracy, private iCloud, lock, VoiceOver and closed-app alerts | Not run; requires physical iPhone acceptance |
| TestFlight upload or public App Store release | Not performed; Apple/GitHub owner setup is still required |

There are **48 native XCTest scenarios in source**: 24 core tests, 17 reminder/OCR tests, 5 model/persistence tests and 2 UI tests. The unsigned macOS CI runs them; the manually dispatched TestFlight workflow requires that validation job to pass before signing/upload. Test source existing does not mean those tests have executed successfully.

The app uses a conservative 60-request notification budget. It verifies actual queue acceptance and exposes the first uncovered time. It does not claim unlimited offline coverage, or guaranteed attention under iOS Focus/Scheduled Summary. Open the app after travel/time-zone changes to renew schedules; closed-app travel behavior is part of physical-device QA.

Preview screenshots are design illustrations made from a separate browser preview. Replace them with captures from the tested native app when preparing App Store screenshots.
