# حالة التحقق | Validation status

Status updated on 3 October 2026. Version 1.0.0, build 2 at commit [7325d7046101](https://github.com/mf103871-boop/Shekati/commit/7325d70461017efe53bec6e44b1d59c54d72220e) passed complete native validation, visual screenshot review, signed archive/export and upload in [run 37147465558](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558). Internal TestFlight readiness is confirmed: the owner-testing group's Builds tab shows `Ready to Test`, `Expires in 90 days`. One owner tester has been added and the invitation was sent; the tester is `Invited`, with acceptance, physical installation and cloud/device acceptance unverified.

| Check | Result |
| --- | --- |
| 36 Swift source files parsed with the Swift tree-sitter grammar | Passed syntax parsing; native compilation and test results are recorded separately below |
| App/bootstrap XcodeGen definitions and all three GitHub workflow YAML files | All five YAML files parsed successfully |
| Twelve embedded workflow Python snippets | Syntax parsed successfully |
| Info, entitlement and privacy plist structures | Parsed successfully |
| Asset catalog JSON and opaque 1024×1024 RGB app icon | Validated |
| Arabic dictionary and direct localization calls | 243 keys, no duplicate keys or missing direct literal translations |
| Interactive preview | Add, amount validation, leading-zero search, filters, settlement, delete/cancel, language, theme and summary controls passed |
| Preview layout | Arabic and English visually inspected; 375px and 320px layouts have no horizontal overflow |
| JavaScript runtime in preview | No page errors during checks |
| Native Swift compilation | Build 2 passed in [run 37147465558](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558), Xcode 26.6 with an iOS 26.5 simulator |
| Foundation core tests on macOS | All 24 passed |
| iPhone SDK test run | All 48 passed: 24 core, 22 hosted unit/integration and 2 UI tests; `TEST SUCCEEDED` |
| Arabic first launch and English language switch UI test | Build 2 passed with the lifecycle fix included; native screenshot review also passed |
| Add-cheque UI test, including leading-zero cheque number | Passed after correcting the offscreen-field test harness |
| Complete native validation job | Build 2 passed: [job 111274269760](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274269760) |
| Settings direction after Arabic-to-English switch | Passed native visual review: English body is readable and unmirrored, left-to-right layout and labels/values are correct, and Settings remains selected |
| Native cloud schema bootstrap tool | iPhone SDK build passed: `BUILD SUCCEEDED`; no cloud initialization or deployment has executed |
| Distribution credentials, signed archive and IPA export | Build 2 succeeded: archive at 19:23:58 UTC and export at 19:23:59 UTC |
| Signed device camera, Vision accuracy, private iCloud, lock, VoiceOver and closed-app alerts | Not run; requires physical iPhone acceptance |
| Binary upload to App Store Connect | Build 2 [job 111274911754](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274911754) passed: `UPLOAD SUCCEEDED`, no errors, 19:25:05 UTC; [saved success proof](screenshots/Shekati-build-upload-success.jpg) |
| Internal TestFlight readiness | Confirmed for [version 1.0.0, build 2](https://appstoreconnect.apple.com/teams/609ff8f7-15ce-48ec-9e60-e95f8ed24d3a/apps/6818852973/testflight/ios/c6a99453-40c5-4cd3-a86b-aeca16550426): group Builds tab shows `Ready to Test`, `Expires in 90 days`; [portal proof](screenshots/Shekati-TestFlight-build.jpg) |
| Earlier portal observations | Main build row showed `Ready to Submit`, and Build Uploads showed `Processing`; the later authoritative internal-group view confirms `Ready to Test` |
| iPhone-only distribution configuration | Signed archive and exported IPA both passed device-family `[1]` guards |
| App Store configuration | US base price [$9.99 saved](screenshots/Shekati-price-saved.jpg); Mac/Vision availability and reduced school volume price unchecked and saved |
| App Store agreements and compliance, read-only | Paid/Free Apps Agreements, US Foreign Status/W-8BEN and DSA active; Brazil tax form has missing information |
| Internal testing group | `Shekati Owner Testing` attached to build 2: one build and one owner tester; automatic distribution off |
| Owner invitation | Sent on 3 October 2026; tester status `Invited`. No confirmed acceptance, device, installation or test session |
| Public App Store release | Not performed |

There are **48 native XCTest scenarios**: 24 core tests, 17 reminder/OCR tests, 5 model/persistence tests and 2 UI tests. All passed in the iPhone test run for build 2 commit [7325d7046101](https://github.com/mf103871-boop/Shekati/commit/7325d70461017efe53bec6e44b1d59c54d72220e), after the macOS core suite also passed. The earlier build 1 also passed 48 tests, but screenshot review exposed a Settings direction defect not detected by its assertions. Build 2 includes the lifecycle fix, passes the renewed tests and passed visual review of the actual native screenshots. Source was unchanged after the successful native validation. A simulator pass does not establish physical-device behavior or cloud synchronization.

The signed build 1 archive and exported IPA succeeded, but App Store Connect rejected that upload with error 90474 because the app target inherited XcodeGen's iPad device-family preset. Build 2 sets the family at the target; both signed archive and IPA family checks passed. Its validation and upload jobs both succeeded. Upload delivery UUID: `c6a99453-40c5-4cd3-a86b-aeca16550426`. The owner-testing group is attached, and its Builds tab confirms `Ready to Test`, `Expires in 90 days`. Earlier `Ready to Submit`/`Processing` observations do not block this confirmed internal readiness. The group has one owner tester, invited on 3 October 2026; status `Invited`. Acceptance and physical-iPhone installation have not been confirmed.

The raw 1260×2736 simulator screenshots came from native artifact `11283221817` for build 2: [Arabic Home](screenshots/native-arabic-home.png), [English cheque detail](screenshots/native-english-detail.png), and [English Settings after language change](screenshots/native-english-settings.png). The English Settings screenshot was visually reviewed and confirms the transition defect is resolved.

The distribution certificate and protected `.p12` were created and verified. All seven required secrets were saved in the `testflight` GitHub environment, restricted to `main`, including the App Store provisioning profile. The local App Store Connect private key was imported into a Windows-user-protected vault and its original downloaded plaintext file was removed after verified import. See [actual account setup status](ACCOUNT_SETUP_STATUS.md).

Read-only App Store Connect Business checks confirmed Paid Apps Agreement Active (25 September 2026–3 September 2027), Free Apps Agreement Active, US Foreign Status and W-8BEN Active, and DSA Active. The Brazil tax form still shows missing information. No agreements were accepted or tax forms changed by the agent during this verification; no bank or personal account details are included here.

Read-only checks of the Windows workstation found no Apple Devices/iTunes installation, Apple Mobile Device Service or Apple USB driver. Local USB-reader preparation is complete, but the user has not yet confirmed connecting an iPhone. No phone identifier has been read, no phone build installed and no native Apple driver/app installed during these checks.

The app uses a conservative 60-request notification budget. It verifies actual queue acceptance and exposes the first uncovered time. It does not claim unlimited offline coverage, or guaranteed attention under iOS Focus/Scheduled Summary. Open the app after travel/time-zone changes to renew schedules; closed-app travel behavior is part of physical-device QA.

Preview screenshots are design illustrations made from a separate browser preview. Replace them with captures from the tested native app when preparing App Store screenshots.
