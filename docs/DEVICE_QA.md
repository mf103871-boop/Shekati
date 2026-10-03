# اختبارات القبول | Device acceptance checklist

Record tester, app/build version, device model, iOS version, date, result and screenshots for each scenario. These are required device checks, not claims that testing has already passed. Use fictional cheques and account references.

## Entry, money and records

- First launch: choose Arabic or English and one currency. Add an incoming and an outgoing cheque using only amount and due date. Save, close and reopen the app; both records and chosen currency remain.
- Verify `001234` remains exactly `001234`. Edit all optional fields, attach front/back images, remove/replace an image, and confirm updates persist.
- Test JPY whole values, USD two decimals and JOD three decimals. Try Arabic and Persian numerals and decimal separators. Reject zero, negative, excess decimals, mixed/grouped formats and overflow. Amount entry uses a decimal separator without thousands grouping.
- Verify settlement defaults the actual date to today, supports another chosen date, and changes the label correctly for incoming/outgoing. Returning/cancelling a cheque does not assign a payment date. An overdue pending cheque remains pending.
- Verify cancellation/deletion, confirmation before delete, successful persistence after restart, and a meaningful error message if saving fails.

## Lists, dashboards and accessibility

- Dashboard outstanding amounts include pending and returned cheques and exclude settled/cancelled ones. Today/next-seven-day/overdue counts agree with the lists opened from those cards.
- Combine number/name/bank search, direction, status, bank and inclusive from/through dates; test empty results and filter reset.
- Check every ascending and descending sort, save choice, reopen, and check ties do not jump randomly.
- In manual sort with a filter, move a visible row. Remove the filter and check hidden rows retain their exact slots. Test a multi-row move and persistence after restart.
- Exercise a fixture of 1,000 records. Search, scrolling, filtering and reordering must remain responsive on the oldest supported test iPhone; retain a measured result rather than assuming simulator speed.
- Check Arabic RTL and English LTR, mixed Latin cheque numbers and Arabic names, system/light/dark appearance, VoiceOver, larger accessibility text and a smaller iPhone screen. Buttons and important labels must not clip.

## Camera and image suggestions

- On a physical iPhone, grant and deny camera access. Photograph a cheque and select an existing image. The manual form remains usable in either case.
- Test clear printed text, Arabic/English layouts, glare, low contrast and handwriting. Unsupported/unreadable fields stay editable. Suggestions must not silently replace user-confirmed values or save without review.
- Verify both images display after restart and on a second iPhone following sync. Confirm image processing occurs without an internet connection.

## Reminders and privacy

- Grant permission when setting a first reminder, and verify defaults of three days, one day and due date at 09:00. Deny permission and verify the Settings link and visible status.
- Customize one cheque's reminder days and time. Verify it uses its overrides while other cheques follow the global defaults; restore defaults and verify it follows the Settings time again.
- Use future times to test a scheduled reminder on an actual locked iPhone while the app is closed and the network is disabled. Check banner content, tap routing and the optional hidden-details mode. OS Focus/Scheduled Summary settings must be documented with the result.
- Edit due date or reminder offsets: old requests disappear and correct new requests are accepted. Settle/cancel/delete: future cheque requests disappear. Returned cheques retain future requests.
- Enable the daily summary and verify due-today and next-three-day content. Disable it and verify corresponding pending requests are removed.
- Create enough future reminders to exceed 60 requests. Verify total accepted app requests never exceeds 60, the first uncovered date is shown, a replenishment request exists, and opening the app refreshes coverage. Trigger/observe an add failure and verify it is visible rather than reported as successful coverage.
- Change time zone across a due date, clock/date, and daylight-saving boundary; reopen and verify the civil due date is unchanged and future local times regenerate correctly. A delivered notification should not mark settlement automatically.
- Enable lock. Background the app: the preview is covered. Tap a cheque notification from the lock screen: authenticate before viewing details. Cancel/fail authentication and verify details remain inaccessible. Confirm device-passcode fallback and disabling lock after authentication.
- Repeat locking with editor, image preview, camera, OCR review and settlement sheets open. The topmost privacy window must cover each sheet, dismiss the keyboard, keep VoiceOver out of covered records, and preserve unsaved drafts after unlocking. Cold-launch with lock already enabled must never show an unlocked first frame.

## iCloud and release readiness

Production schema deployment was verified on 4 October 2026; [Console proof](screenshots/Shekati-iCloud-production-schema.jpg). Regular Shekati **1.0.0 (4)** is available in TestFlight with status `Testing`; [proof](screenshots/Shekati-TestFlight-build4.jpg). App Store Connect reports build 2 installed on the owner's iPhone; update to build 4 before acceptance. Runtime checks below remain pending. If needed, open the app's **Previous Builds**, choose the version and install the available build; [Apple's instructions](https://beta.itunes.apple.com/). Do not uninstall the app or erase its data to perform this check.

For an initial single-phone check, save one fictional incoming cheque with amount `1`, number `SYNC-TEST`, tomorrow's due date and reminders off while online. Record the save time, then inspect Settings. `iCloud available / iCloud متاح` checks account readiness; the **Check iCloud status** button does not force a sync. `Synced / تمت المزامنة` with a new **Last sync** timestamp means a successful import or export event, but does not alone prove every pending record was uploaded. Reopening the app and finding the row confirms local persistence only. Use Production **Logs**, restricted to the test interval and **PRIVATE** database, to verify successful save-operation metadata without opening financial record values. [Apple's Logs documentation](https://developer.apple.com/icloud/logs/) explains that logs show modifications and status, without changed record contents.

For import and round-trip proof, open the same beta on a second unlocked, online iPhone using the same iCloud account. Verify `SYNC-TEST` and the chosen currency arrive without re-entry; edit the marker there and verify the first phone receives the update. A fictional image can extend this check to assets. [Apple's two-device sync guidance](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit).

- Using the registered private production container, add/edit/delete on two iPhones on the same Apple Account and verify eventual propagation of records, images and currency.
- Disconnect one device, edit locally, reconnect and verify eventual sync and honest state indicators. Test unavailable account, network failure and local-store fallback without data loss.
- Test conflicting records/currency after two devices start offline; the app must expose any currency conflict and avoid treating unlike currencies as one total.
- Test App Store/TestFlight Release entitlements and production schema, not only development builds. Core package tests and iPhone XCTest must pass before beta distribution.
- Audit metadata limits, final screenshots, real privacy/support links, paid-download price, tax/banking setup and manual release setting before App Review submission.
