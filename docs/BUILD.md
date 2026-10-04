# البناء والتوقيع | Build and signing

للبدء من ويندوز مع حساب Apple Developer وGitHub مفعّلين، راجع [دليل ربط الحسابات بالعربية](CONNECT_ACCOUNTS_AR.md).

## Current delivery status — build 6 uploaded and processed

The eight [requested improvements](ENHANCEMENTS.md) are implemented at [source 7c5c1a9c68b4](https://github.com/mf103871-boop/Shekati/commit/7c5c1a9c68b4a001fec2a51e8bf198c538089d57). Build **1.0.0 (6)** passed [native job 111350613605](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531/job/111350613605) in [pipeline 37173315531](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531): **113 distinct iPhone scenarios** (29 core, 75 hosted, 9 UI), plus the separate **29-test macOS core suite**, with zero failures. `TEST SUCCEEDED` was recorded at **03:24:26 UTC on 4 October 2026**.

The verified [native attachment artifact 11292218365](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531/artifacts/11292218365) has SHA-256 `132ba833b83309c415d1350d5591b2c5302a361fa054b8fbecaf23440c10caec`. The [signed upload job 111352688429](https://github.com/mf103871-boop/Shekati/actions/runs/37173315531/job/111352688429) passed archive at **03:25:34.969 UTC**, export at **03:25:36.210 UTC** and upload at **03:26:42.472 UTC**, with no errors and successful iPhone-only guards; [upload proof](screenshots/Shekati-build6-upload-success.jpg).

A read-only [official App Store Connect endpoint](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-builds) check at **03:33:14.985 UTC** independently confirmed build 6 as **`processingState: VALID`**, `expired: false`; Apple's `uploadedDate` is **03:30:48 UTC**. The [sanitized processing evidence](build6-processing-state.json) contains only build metadata, with no credentials or token. That check did not assign a testing group or perform any mutation.

The new recently-deleted feature adds optional `ChequeRecord.deletedAt`. Production deployment of **`CD_deletedAt`**, type **Timestamp**, on **`CD_ChequeRecord`** remains pending. CloudKit Console and App Store Connect browser sessions require the owner's sign-in. Automatic tester distribution remains off; do not assign build 6 to the owner group until the additive field is deployed and verified. Build 6 installation and physical-device acceptance are unverified. Build **1.0.0 (5)** remains the last available owner beta and the last portal-confirmed installation. Historical build-5 evidence below covers its earlier binary and schema. See [VALIDATION.md](VALIDATION.md) and [ACCOUNT_SETUP_STATUS.md](ACCOUNT_SETUP_STATUS.md).

## 1. Build the source on a Mac

Use a current stable Xcode, Command Line Tools, an installed iPhone simulator, and XcodeGen 2.42 or newer. The project uses Swift 5 language mode and Swift tools 5.9, with an iOS 17 deployment target. For App Store/TestFlight uploads, use Xcode 26 or newer to meet Apple's current iOS build requirements; check [Apple's upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) before release. Project generation follows the [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).

Run from the repository root:

```sh
brew install xcodegen
swift test --package-path Packages/ShekatiCore
xcodegen generate
open Shekati.xcodeproj
```

Select the shared `Shekati` scheme and an available iPhone simulator. Run the app or use Product → Test. For a command-line test, choose a simulator identifier from `xcrun simctl list devices available` and run:

```sh
xcodebuild test -project Shekati.xcodeproj -scheme Shekati \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

`Shekati.xcodeproj` is generated and ignored; edit `project.yml` for lasting project changes. Both the app and iPhone unit tests link the local `ShekatiCore` package. The shared test scheme includes the package's core tests, the hosted integration tests and the separate `ShekatiUITests` UI-test target. UI-test launches use an isolated in-memory store and test preference suite rather than real financial records.

Simulator builds deliberately use local-only storage, including hosted unit-test startup, to avoid querying CloudKit from an unsigned process. Verify actual private iCloud using signed physical-iPhone builds. UI-test launch also disables reminder days by default to avoid a system permission dialog during automated entry checks.

## 2. Build from Windows using GitHub Actions

Create a GitHub repository and place this folder's contents at its root, including the hidden `.github` directory. Enable Actions. The **Build and test iPhone app** workflow runs on pushes, pull requests, or manual dispatch. It runs core tests, generates the project, selects an available iPhone simulator, and executes the hosted integration tests and XCUITest target. The current suite also covers populated build-5 store migration, backup/CSV safety, filtered ordering, notification refresh identity and a 1,000-cheque on-disk store with 2,000 valid JPEG images. Its `.xcresult` report retains timing measurements and UI attachments. Measurement fixtures are separate from timed list work; no unstable CI speed threshold is imposed. These automated checks do not replace scrolling/memory profiling, camera, real iCloud, biometric and closed-app notification checks on physical iPhones.

For screenshot review on Windows, download **Shekati-native-ui-attachments** from the successful run and unzip it locally. CI exports the raw PNG attachments with `xcresulttool`; the separate **Shekati-simulator-test-report** contains the `.xcresult` report. On a Mac, the equivalent export command is:

```sh
xcrun xcresulttool export attachments --path build/Shekati.xcresult --output-path build/ui-attachments
```

Historical build 5 at [source 8f806ae2a3d3](https://github.com/mf103871-boop/Shekati/commit/8f806ae2a3d370dcab6c1cc7597c9d4a8d503ce6), [run 37164184467](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467), passed 24 macOS core tests and 58 distinct iPhone scenarios (24 core, 30 hosted, 4 UI). Nine raw iPhone Air PNGs are saved as `docs/screenshots/native-build5-*.png`; [validation details](VALIDATION.md) include attachment artifact `11288454780` and its SHA-256. They show the build-5 interface rather than the eight new improvements.

No Apple credentials are needed for that unsigned simulator check. Workflow execution still requires a repository and the owner's GitHub account; files alone do not start a remote build. GitHub's hosted macOS runners supply the build host, and private repositories may use paid minutes. See [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## 3. Configure an account-owned app and private iCloud container

1. The owner's explicit app identifier `com.mf103871.shekati` has been registered. If building for another account, register your own unique identifier and update the project.
2. The owner's container `iCloud.com.mf103871.shekati` has been registered and associated with this app's iCloud/CloudKit capability. Push Notifications is enabled. If building for another account, register and associate your own container.
3. On a Mac, update `PRODUCT_BUNDLE_IDENTIFIER` and `SHEKATI_ICLOUD_CONTAINER` in `project.yml`, generate again, and choose the owning development team. For the hosted signed workflow, supply these values as dispatch inputs instead.
4. Keep the custom Info key `ShekatiCloudContainerIdentifier` and the iCloud entitlement consistent; both expand the same `SHEKATI_ICLOUD_CONTAINER` setting. Background remote notifications support CloudKit's silent sync signals. Cheque reminders remain local.
5. Run a **signed development build** with the real container and an iCloud account to initialize its development schema. Inspect the records in CloudKit Console and deploy the schema to Production before TestFlight. A simulator build without signing/account access does not prove cloud sync. A developer Mac or correctly provisioned registered-device development build is needed for this first schema step.
6. Test private sync on two iPhones signed into the same Apple Account. Records and currency are synced; appearance, language, reminder settings and app-lock settings remain device preferences. Sync status reflects CloudKit events/account/network state; it is not a guarantee of instant propagation. See [Apple's SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

The model deliberately avoids unique constraints and gives nonoptional properties defaults for CloudKit compatibility. Dates are stored as Gregorian date-only strings, images as optional external-storage data. Do not change model types or delete the store to bypass a migration failure; plan and test a migration first.

### Additive schema update for recently deleted cheques

Build 6 retains every existing entity and attribute and adds only optional `deletedAt: Date?` to `ChequeRecord`. The corresponding CloudKit field is **`CD_deletedAt`**, type **Timestamp**, on **`CD_ChequeRecord`**. `Timestamp` is the Console field type, not part of the field name. Apple documents the `CD_` attribute mapping and date conversion in [Reading CloudKit records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data).

With the owning account signed in, review the Development schema and add the field using the same index options as the existing date attributes, or run the updated [development schema tool](../Tools/SchemaBootstrap/README.md) with current source and its existing registered-device profile. The tool uses a separate temporary store; it must not replace or reset the user's regular database. Review **Deploy Schema Changes**, deploy the additive change and inspect Production for the exact field/type before beta assignment. Preserve a new Production screenshot separately from the historical build-5 capture. [Apple's schema deployment guidance](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema) explains the additive Production restrictions.

The full encrypted backup is the recovery format for images, currency, order, deleted state and reminder overrides. CSV transfers selected cheque fields; PDF is a readable report. Recovered records merge by UUID, with replacement of existing records disabled by default. See [recovery boundaries](ENHANCEMENTS.md) before testing restore or permanent deletion.

Use build 6 on both phones for cross-device trash acceptance. Build 5 does not recognize soft deletion and may continue to display or remind about a cheque trashed by the new version. Updating the schema alone does not update the older binary's behavior.

## 4. Prepare signing and manually upload to TestFlight

Create the App Store Connect app record for the owned Bundle ID. Create an **Apple Distribution** certificate, export it with its private key as a password-protected `.p12`, and create an **App Store distribution provisioning profile** with the same Bundle ID, team, Push Notifications and private iCloud container. Provisioning material must be obtained through the owning Apple account; this source delivery contains none.

Create an App Store Connect API key with permission to upload builds. Add these secrets to a GitHub environment named `testflight`:

| Secret | Value |
| --- | --- |
| `DISTRIBUTION_CERTIFICATE_BASE64` | Base64 contents of the `.p12` file |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | The export password for that `.p12` |
| `APPSTORE_PROVISIONING_PROFILE_BASE64` | Base64 contents of the distribution `.mobileprovision` file |
| `KEYCHAIN_PASSWORD` | A strong temporary-keychain password chosen for CI |
| `ASC_KEY_ID` | App Store Connect API key identifier |
| `ASC_ISSUER_ID` | App Store Connect issuer identifier |
| `ASC_PRIVATE_KEY_BASE64` | Base64 contents of the API key `.p8` file |

On Windows, copy a file's base64 encoding without printing its contents into a command log:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\certificate.p12')) | Set-Clipboard
```

Repeat for the provisioning profile and API private key, substituting the actual private file path. Paste into the GitHub secret form. Do not paste keys in chat or commit them. GitHub supports optional environment reviewer restrictions subject to repository-plan availability; see [environment configuration](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

Manually run **Upload manually to TestFlight**. Supply the owned Bundle ID, actual container ID, ten-character Team ID, and a unique positive integer build number. The workflow first calls the full unsigned CI workflow for core, integration and UI tests; signing/upload starts only after it passes. It validates inputs/profile, imports credentials into a temporary keychain, generates a signed Release archive, exports the IPA, and uploads it for App Store Connect processing. Credentials are removed at the end, and no private IPA is published as an artifact. Upload and processing may complete while a schema update is pending, with automatic tester distribution kept off; do not assign build 6 to a testing group until the new Production deletion field is deployed and verified.

The workflow uploads a build only. It does not invite testers, submit for App Review, change the price, or release the app publicly. Configure TestFlight test information and internal/external testing in App Store Connect after processing; external testing may require Apple's beta review. See [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

Historical build 5's [upload job 111324443434](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467/job/111324443434) passed signed archive at 00:18:01 UTC, IPA export at 00:18:02 UTC and upload at 00:19:04 UTC with no errors. Archive and IPA device-family `[1]` guards passed. Processing completed, and `1.0.0 (5)` was manually added to the existing owner group as `Testing`, `Expires in 90 days`. A fresh portal view confirmed `Installed 1.0.0 (5)` on 4 October; actual phone UI, private iCloud and notification QA remain unverified. See [TestFlight proof](screenshots/Shekati-TestFlight-build5.jpg) and [upload proof](screenshots/Shekati-build5-upload-success.jpg). Build 6 upload/processing/assignment/installation must be recorded independently when each succeeds.

## 5. App Store release checklist

- Complete the device QA matrix and retain actual results. Resolve compile, test, sync and device failures before submission.
- Replace operator/contact placeholders, publish the privacy and support pages on actual accessible URLs, and put those URLs in App Store Connect.
- Review the privacy manifest and App Privacy questionnaire against the final binary and any later SDKs. Current source has no analytics, ads, tracking or developer-operated backend.
- Add genuine iPhone screenshots captured from the running app in Arabic and English; design previews are not App Store screenshots.
- Enable only iPhone distribution; opt out of Mac and Apple Vision Pro availability in App Store Connect as well as the project build settings.
- Complete tax/banking details and accept the Paid Apps Agreement. Set United States as the base storefront, **$9.99** as the paid-download base price, and use Apple's comparable local prices. No in-app products are required. See [Apple app pricing](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/).
- Confirm age rating, Finance category, encryption/export compliance, review contact details and trademark/name availability, then submit with manual public release selected.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| No iPhone simulator in CI | Install an iOS runtime/select an available hosted image; inspect the simulator-selection error |
| Signing/profile mismatch | Recreate the profile for the owned Bundle ID/team/container and corresponding distribution certificate |
| CloudKit unavailable | Check Apple Account, network, entitlements and production schema; preserve the local store |
| Local-only fallback shown | Records remain local in the same store; fix cloud configuration and restart before testing sync |
| Missing notification | Inspect OS permission, Focus/Scheduled Summary and the app's accepted coverage status; open the app to replenish |
| Travel/time-zone change | Open the app after changing time zone to regenerate and inspect local schedules; closed-app time-zone adaptation still requires device verification |
| Upload succeeds but no build visible yet | Wait for Apple's processing, then inspect processing errors in App Store Connect |
