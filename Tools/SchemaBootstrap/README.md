# Prepare the CloudKit schema from Windows

This separate iPhone setup app builds on GitHub's macOS runner and initializes the complete development schema on an iCloud-enabled, registered iPhone. It compiles the same `ChequeRecord.swift` source and `ShekatiCore` package as the regular app. The production app and its project do not include this setup target.

The **Start setup** button calls Apple's SwiftData-to-Core-Data model conversion and `initializeCloudKitSchema`. Core Data creates temporary records for every type and field, including optional fields and asset counterparts, then removes those records. The setup app uses a temporary local store. Keep it open until completion. See [Apple's SwiftData initialization guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) and [the dedicated-target recommendation](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users).

## Inputs needed once

- A registered iPhone running iOS 17 or later, with iCloud signed in and iCloud Drive enabled. Registration uses the phone's UDID.
- A dedicated explicit setup App ID, `com.mf103871.shekati.schema-setup`, in the Shekati developer team. Enable Push Notifications and iCloud with CloudKit support. Assign **the existing** `iCloud.com.mf103871.shekati` container to the setup ID. Apple supports sharing a container between apps. [Assign an existing container](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
- An Apple Distribution signing certificate with its private key and password, plus an **ad-hoc distribution provisioning profile** for that setup ID, the existing distribution certificate, and just the owner’s registered iPhone. [Create an ad hoc profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)

Connect the phone to the Windows computer with USB, unlock it, and tap **Trust** when prompted. The device tool below can read its identifier locally, so there is no need to copy identifiers into repository files. Developer Mode may be required to run the exported IPA; enable it on the phone under Settings → Privacy & Security and complete the on-device restart/confirmation. See [Apple's registered-device distribution guidance](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

The independent app appears as **Shekati Sync Setup** with its own installation and temporary local store. Save the setup-specific profile in the existing signing environment. The release app keeps its current App ID and distribution profile.

## Compile and export through GitHub Actions

The **Prepare CloudKit schema setup app** workflow defaults to an unsigned compile. Running it with **Export a signed setup IPA** unchecked checks the source without credentials or an iCloud login on the runner.

For a signed export, configure these repository or `testflight` environment secrets. The existing signing certificate and keychain secrets can be reused; the ad-hoc profile is the additional device-specific value:

| Secret | Contents |
| --- | --- |
| `DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the certificate and private key |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `SCHEMA_SETUP_ADHOC_PROFILE_BASE64` | Base64-encoded ad-hoc `.mobileprovision` for the dedicated setup App ID and owner’s iPhone |
| `KEYCHAIN_PASSWORD` | Password for the runner's temporary signing keychain |

Select the signed export option and supply the Bundle ID, container, Team ID, and build number. The workflow compiles the setup app, exports an IPA using the **Development** CloudKit environment, checks the signed app's actual entitlements, then encrypts the verified IPA for the owner. The downloadable artifact contains only the CMS envelope and expires after three days. The pinned public recipient certificate is checked into this repository. Its private key stays in the owner’s protected workspace. Ad-hoc distribution uses production APNs independently of the selected CloudKit environment. This workflow does not submit a build to App Store Connect or change the cloud schema; initialization happens on the phone after the button press. Apple's [CloudKit testing guide](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html) supports selecting Development for ad-hoc builds.

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

Download and unzip **ShekatiSchemaBootstrap-encrypted-iPhone**. The GitHub repository is public. Its artifact contains only `ShekatiSchemaBootstrap.ipa.cms`. The runner verifies the code signature, embedded device profile and Development entitlements, then encrypts the signed IPA with OpenSSL 3 using the checked-in RSA recipient certificate. [GitHub artifact access](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts) · [OpenSSL CMS options](https://docs.openssl.org/3.5/man1/openssl-cms/)

```sh
openssl cms -encrypt -binary -aes-256-gcm -outform DER \
  -recip Tools/SchemaBootstrap/setup-delivery-recipient.pem \
  -keyopt rsa_padding_mode:oaep -keyopt rsa_oaep_md:sha256 -keyopt rsa_mgf1_md:sha256 \
  -in ShekatiSchemaBootstrap.ipa -out ShekatiSchemaBootstrap.ipa.cms
```

On the owner's workstation, work inside an owner-only directory. Set `$openssl3` to the local OpenSSL 3 executable, `$recipient` to the public certificate, and `$ownerKey` to the encrypted private delivery key held locally. Set `$checker` to the checked-out `Tools/SchemaBootstrap/verify_setup_ipa.py` script. The private key passphrase is entered locally. Decrypt to a new temporary file and verify that the authenticated operation succeeds before using its contents.

```powershell
$staged = Join-Path $PWD ([guid]::NewGuid().ToString() + '.ipa.part')
try {
    & $openssl3 cms -decrypt -binary -inform DER -in ShekatiSchemaBootstrap.ipa.cms -recip $recipient -inkey $ownerKey -out $staged
    if ($LASTEXITCODE -ne 0) { throw 'CMS decryption or authentication failed.' }
    py $checker $staged
    if ($LASTEXITCODE -ne 0) { throw 'The decrypted file is not the standalone setup IPA.' }
    Move-Item -LiteralPath $staged -Destination ShekatiSchemaBootstrap.ipa -ErrorAction Stop
} finally {
    if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged }
}
```

After the verified IPA is available, its owner can install it on the registered phone:

```powershell
.\.schema-device-tools\Scripts\python.exe -m pymobiledevice3 apps install 'C:\path\ShekatiSchemaBootstrap.ipa'
```

For multiple connected devices, select the intended identifier with the command's `--udid` option. Installation support is provided by that third-party project and must be verified on the actual phone and iOS version. The plaintext IPA and its embedded device profile stay in the protected local directory.

## Initialize, review, and deploy

1. Open **Shekati Sync Setup** on the registered iPhone, then tap **Start setup**. Remain in the app until the success message appears.
2. Open [CloudKit Console](https://icloud.developer.apple.com/), choose the intended team and container, and inspect the **Development** record types. Confirm `CD_ChequeRecord`, `CD_AppConfiguration`, `CD_BankAccountRecord`, `CD_ChequeBookRecord` and `CD_LedgerEventRecord`, including generated asset fields and indexes. Compare the release checkout and exported schema with [the ledger schema verifier and release checklist](../../docs/LEDGER_CLOUD_RELEASE_AR.md). See [Core Data's documented record mapping](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data).
3. Choose **Deploy Schema Changes**, review the pending changes, and deploy them to Production. This copies the schema, not development records. Apple requires production-edit privileges for this step. See [Apple's deployment instructions](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
4. Install the regular TestFlight app and verify signed-device iCloud export/import. Local cheque tracking can be tested before schema deployment; production sync requires the deployed schema.

## Why the App Store Connect API key alone is insufficient

Apple documents a separate **CloudKit Management Token** from CloudKit Console for `cktool` and CKTool JS. `export-schema` downloads a schema that already exists on the server; `import-schema` applies an existing `.ckdb` file to Development. These APIs do not convert the SwiftData source into that schema. `dryRun` and `printSchema` validate/generate records and print them; they are not a documented `.ckdb` exporter. No additional token is needed for the registered-phone path above. See [CloudKit automation authentication](https://developer.apple.com/icloud/cloudkit/automating/), [cktool](https://developer.apple.com/icloud/ck-tool/), and [schema initialization options](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainerschemainitializationoptions).

The source, YAML, embedded Python, and plist files have static validation. The native iOS build succeeded on hosted macOS in [build 2 validation, job 111274269760](https://github.com/mf103871-boop/Shekati/actions/runs/37147465558/job/111274269760). On 4 October 2026, the registered-phone setup [run 37158554652](https://github.com/mf103871-boop/Shekati/actions/runs/37158554652) also passed validation, Debug ad-hoc archive/export, code-signature verification, Development CloudKit entitlement and iPhone-only guards. The verified build 3 IPA was installed through USB on the intended iPhone, with its executable and build confirmed by a scoped lookup. The user's phone screenshot subsequently confirmed **Initialization completed** in Development for `iCloud.com.mf103871.shekati`.

CloudKit Console review verified every model field, generated asset counterpart and framework field: `CD_ChequeRecord` has 40 record fields plus 6 metadata fields; `CD_AppConfiguration` has 7 record fields plus 6 metadata fields. The deployment diff added these two record types and their 62 and 13 indexes, with the generated built-in role grants. Deployment completed, and a separate Production read confirmed identical field names, types and index settings for both types; [Production proof](../../docs/screenshots/Shekati-iCloud-production-schema.jpg). Schema deployment does not demonstrate a successful export/import of real app records. Regular TestFlight build 1.0.0 (4) is now available; the portal reports build 2 installed on the owner's iPhone. Updating to build 4 and signed-device private iCloud acceptance are still required.
