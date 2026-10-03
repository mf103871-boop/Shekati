# Prepare the CloudKit schema from Windows

This separate iPhone setup app builds on GitHub's macOS runner and initializes the complete development schema on an iCloud-enabled, registered iPhone. It compiles the same `ChequeRecord.swift` source and `ShekatiCore` package as the regular app. The production app and its project do not include this setup target.

The **Start setup** button calls Apple's SwiftData-to-Core-Data model conversion and `initializeCloudKitSchema`. Core Data creates temporary records for every type and field, including optional fields and asset counterparts, then removes those records. The setup app uses a temporary local store. Keep it open until completion. See [Apple's SwiftData initialization guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) and [the dedicated-target recommendation](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users).

## Inputs needed once

- A registered iPhone running iOS 17 or later, with iCloud signed in and iCloud Drive enabled. Registration uses the phone's UDID.
- The account-owned Bundle ID, CloudKit container identifier, and Team ID. Enable CloudKit and push notifications for the App ID and attach the container.
- An Apple Distribution signing certificate with its private key and password, plus an **ad-hoc distribution provisioning profile** that includes that App ID, container, and intended iPhone.

Connect the phone to the Windows computer with USB, unlock it, and tap **Trust** when prompted. The device tool below can read its identifier locally, so there is no need to copy identifiers into repository files. Developer Mode may be required to run the exported IPA; enable it on the phone under Settings → Privacy & Security and complete the on-device restart/confirmation. See [Apple's registered-device distribution guidance](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

If you give this setup build the regular app's Bundle ID, installation replaces the installed Shekati binary. Perform initial setup before entering real cheques. The setup tool does not open the regular app's local database.

## Compile and export through GitHub Actions

The **Prepare CloudKit schema setup app** workflow defaults to an unsigned compile. Running it with **Export a signed setup IPA** unchecked checks the source without credentials or an iCloud login on the runner.

For a signed export, configure these repository or `testflight` environment secrets. The existing signing certificate and keychain secrets can be reused; the ad-hoc profile is the additional device-specific value:

| Secret | Contents |
| --- | --- |
| `DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the certificate and private key |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `ADHOC_PROVISIONING_PROFILE_BASE64` | Base64-encoded ad-hoc `.mobileprovision` for the registered phone |
| `KEYCHAIN_PASSWORD` | Password for the runner's temporary signing keychain |

Select the signed export option and supply the Bundle ID, container, Team ID, and build number. The workflow compiles the setup app, exports an IPA using the **Development** CloudKit environment, checks the signed app's actual entitlements, and saves a private download artifact for three days. Ad-hoc distribution uses production APNs independently of the selected CloudKit environment. This workflow does not submit a build to App Store Connect or change the cloud schema; initialization happens on the phone after the button press. Apple's [CloudKit testing guide](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html) supports selecting Development for ad-hoc builds.

For local Mac compilation, the equivalent commands are:

```sh
xcodegen generate --spec Tools/SchemaBootstrap/project.yml --project Tools/SchemaBootstrap
xcodebuild build -project Tools/SchemaBootstrap/ShekatiSchemaBootstrap.xcodeproj \
  -scheme ShekatiSchemaBootstrap -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## Install the signed IPA from Windows using USB

`pymobiledevice3` is an independent open-source device tool. Its maintainers document Windows support and a local IPA installation command. Use Apple Devices or iTunes for Apple's USB drivers, keep the phone connected by cable, and install the Python package in a dedicated environment. This tool does not need an Apple account password to install an already-signed, correctly provisioned IPA. See the project's [installation guide](https://doronz88.github.io/pymobiledevice3/installation/) and [installation command source](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/apps.py).

Example PowerShell commands with a local Python installation:

```powershell
py -m venv .schema-device-tools
.\.schema-device-tools\Scripts\python.exe -m pip install pymobiledevice3
.\.schema-device-tools\Scripts\python.exe -m pymobiledevice3 usbmux list
```

Download and unzip the private workflow artifact. With exactly one intended iPhone connected and trusted:

```powershell
.\.schema-device-tools\Scripts\python.exe -m pymobiledevice3 apps install 'C:\path\ShekatiSchemaBootstrap.ipa'
```

For multiple connected devices, select the intended identifier with the command's `--udid` option. Installation support is provided by that third-party project and must be verified on the actual phone and iOS version. The artifact remains private; public IPA hosting is unnecessary.

## Initialize, review, and deploy

1. Open **Shekati Sync Setup** on the registered iPhone, then tap **Start setup**. Remain in the app until the success message appears.
2. Open [CloudKit Console](https://icloud.developer.apple.com/), choose the intended team and container, and inspect the **Development** record types. Confirm `CD_ChequeRecord` and `CD_AppConfiguration`, all model fields, and generated asset fields. Use the actual production source as the checklist. See [Core Data's documented record mapping](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data).
3. Choose **Deploy Schema Changes**, review the pending changes, and deploy them to Production. This copies the schema, not development records. Apple requires production-edit privileges for this step. See [Apple's deployment instructions](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
4. Install the regular TestFlight app and verify signed-device iCloud export/import. Local cheque tracking can be tested before schema deployment; production sync requires the deployed schema.

## Why the App Store Connect API key alone is insufficient

Apple documents a separate **CloudKit Management Token** from CloudKit Console for `cktool` and CKTool JS. `export-schema` downloads a schema that already exists on the server; `import-schema` applies an existing `.ckdb` file to Development. These APIs do not convert the SwiftData source into that schema. `dryRun` and `printSchema` validate/generate records and print them; they are not a documented `.ckdb` exporter. No additional token is needed for the registered-phone path above. See [CloudKit automation authentication](https://developer.apple.com/icloud/cloudkit/automating/), [cktool](https://developer.apple.com/icloud/ck-tool/), and [schema initialization options](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainerschemainitializationoptions).

The source, YAML, embedded Python, and plist files have static validation. The native iOS build succeeded on hosted macOS in [build 2 validation, job 111274269760](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274269760). On 4 October 2026, the registered-phone setup [run 37158554652](https://github.com/mf103871-boop/Shekati/actions/runs/37158554652) also passed validation, Debug ad-hoc archive/export, code-signature verification, Development CloudKit entitlement and iPhone-only guards. The verified build 3 IPA was installed through USB on the intended iPhone, with its executable and build confirmed by a scoped lookup. The user's phone screenshot subsequently confirmed **Initialization completed** in Development for `iCloud.com.mf103871.shekati`.

CloudKit Console review verified every model field, generated asset counterpart and framework field: `CD_ChequeRecord` has 40 record fields plus 6 metadata fields; `CD_AppConfiguration` has 7 record fields plus 6 metadata fields. The deployment diff added these two record types and their 62 and 13 indexes, with the generated built-in role grants. Deployment completed, and a separate Production read confirmed identical field names, types and index settings for both types; [Production proof](../../docs/screenshots/Shekati-iCloud-production-schema.jpg). Schema deployment does not demonstrate a successful export/import of real app records. Regular TestFlight build 1.0.0 (4) is now available; the portal reports build 2 installed on the owner's iPhone. Updating to build 4 and signed-device private iCloud acceptance are still required.
