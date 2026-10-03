# حالة التحقق | Validation status

Updated on 3 October 2026. Source preparation took place on Windows, and native compilation and tests have now executed on hosted macOS. The following distinguishes successful checks, the remaining CI failure and device checks still pending.

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
| Native Swift compilation | Passed in [run 37145564552](https://github.com/mf103871-boop/Shekati/actions/runs/37145564552), Xcode 26.6 with an iOS 26.5 simulator |
| Foundation core tests | All 24 passed in run 37145564552 |
| Hosted reminder/OCR and model/persistence tests | All 22 passed in run 37145564552 |
| Arabic first launch and English language switch UI test | Passed in run 37145564552 |
| Add-cheque UI test, including leading-zero cheque number | Failed because the test harness could not reach an offscreen field; [retry 37146039264](https://github.com/mf103871-boop/Shekati/actions/runs/37146039264) still failed at `partyField`; its simulator result is under review |
| Complete native validation run | Failed in both runs; the add-cheque UI scenario remains unresolved |
| Signed device camera, Vision accuracy, private iCloud, lock, VoiceOver and closed-app alerts | Not run; requires physical iPhone acceptance |
| TestFlight upload or public App Store release | Not performed; accounts and all seven signing/upload secrets are connected, but the complete CI pass and cloud schema setup remain pending |

There are **48 native XCTest scenarios in source**: 24 core tests, 17 reminder/OCR tests, 5 model/persistence tests and 2 UI tests. In both runs, 47 passed and the add-cheque UI scenario failed. The retry's [test job 111270065446](https://github.com/mf103871-boop/Shekati/actions/runs/37146039264/job/111270065446) completed with failure. The manually dispatched TestFlight workflow requires the complete validation job to pass before signing/upload. A simulator pass does not establish physical-device behavior or cloud synchronization.

The distribution certificate and protected `.p12` were created and verified. All seven required secrets were saved in the `testflight` GitHub environment, restricted to `main`, including the App Store provisioning profile. The local App Store Connect private key was imported into a Windows-user-protected vault and its original downloaded plaintext file was removed after verified import. See [actual account setup status](ACCOUNT_SETUP_STATUS.md).

The app uses a conservative 60-request notification budget. It verifies actual queue acceptance and exposes the first uncovered time. It does not claim unlimited offline coverage, or guaranteed attention under iOS Focus/Scheduled Summary. Open the app after travel/time-zone changes to renew schedules; closed-app travel behavior is part of physical-device QA.

Preview screenshots are design illustrations made from a separate browser preview. Replace them with captures from the tested native app when preparing App Store screenshots.
