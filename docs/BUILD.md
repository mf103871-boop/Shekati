# البناء والتوقيع | Build and signing

للبدء من ويندوز مع حساب Apple Developer وGitHub مفعّلين، راجع [دليل ربط الحسابات بالعربية](CONNECT_ACCOUNTS_AR.md).

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

Create a GitHub repository and place this folder's contents at its root, including the hidden `.github` directory. Enable Actions. The **Build and test iPhone app** workflow runs on pushes, pull requests, or manual dispatch. It runs core tests, generates the project, selects an available iPhone simulator, and executes the hosted integration tests and XCUITest target. Its `.xcresult` report is retained as a workflow artifact. These automated UI checks do not replace camera, real iCloud, biometric and closed-app notification checks on physical iPhones.

No Apple credentials are needed for that unsigned simulator check. Workflow execution still requires a repository and the owner's GitHub account; files alone do not start a remote build. GitHub's hosted macOS runners supply the build host, and private repositories may use paid minutes. See [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## 3. Configure an account-owned app and private iCloud container

1. Enroll in the Apple Developer Program and register a unique explicit app identifier. `com.shekati.app` is a sample identifier to replace.
2. Register the app's CloudKit container. `iCloud.com.shekati.app` is a sample identifier to replace. Enable iCloud/CloudKit and Push Notifications for the app identifier and associate the container.
3. On a Mac, update `PRODUCT_BUNDLE_IDENTIFIER` and `SHEKATI_ICLOUD_CONTAINER` in `project.yml`, generate again, and choose the owning development team. For the hosted signed workflow, supply these values as dispatch inputs instead.
4. Keep the custom Info key `ShekatiCloudContainerIdentifier` and the iCloud entitlement consistent; both expand the same `SHEKATI_ICLOUD_CONTAINER` setting. Background remote notifications support CloudKit's silent sync signals. Cheque reminders remain local.
5. Run a **signed development build** with the real container and an iCloud account to initialize its development schema. Inspect the records in CloudKit Console and deploy the schema to Production before TestFlight. A simulator build without signing/account access does not prove cloud sync. A developer Mac or correctly provisioned registered-device development build is needed for this first schema step.
6. Test private sync on two iPhones signed into the same Apple Account. Records and currency are synced; appearance, language, reminder settings and app-lock settings remain device preferences. Sync status reflects CloudKit events/account/network state; it is not a guarantee of instant propagation. See [Apple's SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

The model deliberately avoids unique constraints and gives nonoptional properties defaults for CloudKit compatibility. Dates are stored as Gregorian date-only strings, images as optional external-storage data. Do not change model types or delete the store to bypass a migration failure; plan and test a migration first.

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

After the cloud production schema is deployed, manually run **Upload manually to TestFlight**. Supply the owned Bundle ID, actual container ID, ten-character Team ID, and a unique positive integer build number. The workflow first calls the full unsigned CI workflow for core, integration and UI tests; signing/upload starts only after it passes. It validates inputs/profile, imports credentials into a temporary keychain, generates a signed Release archive, exports the IPA, and uploads it for App Store Connect processing. Credentials are removed at the end, and no private IPA is published as an artifact.

The workflow uploads a build only. It does not invite testers, submit for App Review, change the price, or release the app publicly. Configure TestFlight test information and internal/external testing in App Store Connect after processing; external testing may require Apple's beta review. See [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

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
