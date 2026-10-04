import SwiftUI
import SwiftData
import LocalAuthentication
import UserNotifications

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @State private var showCurrencies = false
    @State private var lockUnavailable = false
    @State private var customOffset = ""

    var body: some View {
        @Bindable var preferences = app.preferences
        Form {
            Section {
                HStack(spacing: 16) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.tr("Shekati")).font(.title2.bold())
                            .accessibilityIdentifier("settingsBrandTitle")
                        Text(app.tr("Every cheque, at a glance.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section(app.tr("Appearance and language")) {
                Picker(app.tr("Language"), selection: $preferences.language) {
                    Text("العربية").tag(AppLanguage.arabic)
                    Text("English").tag(AppLanguage.english)
                }
                .accessibilityIdentifier("languagePicker")
                .pickerStyle(.menu)
                Picker(app.tr("Appearance"), selection: $preferences.appearance) {
                    Text(app.tr("System")).tag(AppAppearance.system)
                    Text(app.tr("Light")).tag(AppAppearance.light)
                    Text(app.tr("Dark")).tag(AppAppearance.dark)
                }
                .pickerStyle(.menu)
                Button { showCurrencies = true } label: {
                    HStack { Text(app.tr("Currency")); Spacer(); Text(app.currencyCode).foregroundStyle(.secondary) }
                }.disabled(!records.isEmpty)
                if !records.isEmpty {
                    Text(app.tr("Currency cannot change while any saved cheque exists, including history."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                notificationPermission
                reminderToggle("3 days before", offset: 3)
                reminderToggle("1 day before", offset: 1)
                reminderToggle("On the due date", offset: 0)
                let extra = preferences.reminderOffsets.filter { ![3, 1, 0].contains($0) }.sorted()
                ForEach(extra, id: \.self) { offset in
                    HStack {
                        Text(Localization.daysBefore(offset, language: app.preferences.language))
                        Spacer()
                        Button(role: .destructive) { preferences.reminderOffsets.removeAll { $0 == offset } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel(app.tr("Remove reminder"))
                    }
                }
                HStack {
                    TextField(app.tr("Days before"), text: $customOffset).keyboardType(.numberPad)
                    Button(app.tr("Add")) {
                        if let value = customOffsetValue, (0...365).contains(value) {
                            preferences.reminderOffsets = Array(Set(preferences.reminderOffsets + [value])).sorted(by: >)
                            customOffset = ""
                        }
                    }.disabled(customOffsetValue.map { !(0...365).contains($0) } ?? true)
                }
                DatePicker(app.tr("Reminder time"), selection: timeBinding, displayedComponents: .hourAndMinute)
                Toggle(app.tr("Daily summary"), isOn: $preferences.dailySummary)
                Toggle(app.tr("Hide notification details"), isOn: $preferences.hideNotificationDetails)
                LabeledContent(app.tr("Scheduled notifications"), value: app.notifications.scheduledCount.formatted())
                if app.notifications.authorizationStatus != .notDetermined,
                   !app.notifications.isDenied, let date = app.notifications.firstUncoveredDate {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.tr("First reminder not scheduled")).font(.subheadline.weight(.semibold))
                        Text(app.formatTimestamp(date)).font(.footnote)
                        Text(app.tr("Open the app before this time to renew the queue. Later reminders are not yet covered."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }.foregroundStyle(.orange)
                }
                if let message = app.notifications.message {
                    Text(message)
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button(app.tr("Refresh reminders")) { app.didMutate() }
            } header: { Text(app.tr("Reminders")) } footer: {
                Text(app.tr("Defaults apply to cheques without custom reminders. Daily summaries include today and the next 3 days. Scheduled alerts work offline; a large queue needs periodic renewal."))
            }
            Section {
                Toggle(app.tr("Lock app"), isOn: Binding(get: { preferences.appLockEnabled }, set: { enabled in
                    if enabled {
                        let authentication = LAContext()
                        var error: NSError?
                        guard authentication.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                            lockUnavailable = true; return
                        }
                    }
                    preferences.appLockEnabled = enabled
                }))
            } header: { Text(app.tr("Privacy")) } footer: {
                Text(app.tr("Use Face ID, Touch ID or your device passcode. App previews are hidden when locking is enabled."))
            }
            Section(app.tr("iCloud")) {
                Label(syncLabel, systemImage: syncSymbol)
                if let last = app.sync.lastSyncDate {
                    LabeledContent(app.tr("Last sync"), value: app.formatTimestamp(last))
                }
                Text(app.tr("Cheques, photos, manual order and currency sync through your Apple account. Reminder defaults, language and lock are specific to this iPhone."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(app.tr("Check iCloud status")) { Task { await app.sync.refresh() } }
            }
            Section(app.tr("Your data")) {
                NavigationLink(app.tr("Data and backup")) { DataToolsView() }
                    .accessibilityIdentifier("dataTools")
                NavigationLink(app.tr("Recently deleted")) { TrashView() }
                    .accessibilityIdentifier("recentlyDeleted")
            }
            Section(app.tr("About")) {
                LabeledContent(app.tr("Version"), value: version)
                Text(app.tr("All features included. One purchase. No subscription."))
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink(app.tr("Privacy policy")) { PrivacyPolicyView() }
            }
        }
        // UIKit-backed forms can retain an RTL transform when direction changes in place.
        // Rebuild the form while keeping this screen's state and the selected tab intact.
        .id(app.preferences.language.rawValue)
        .navigationTitle(app.tr("Settings"))
            .sheet(isPresented: $showCurrencies) { NavigationStack { CurrencyPickerView() } }
            .alert(app.tr("Device lock unavailable"), isPresented: $lockUnavailable) {
                Button(app.tr("OK"), role: .cancel) {}
            } message: { Text(app.tr("Set a device passcode in iPhone Settings before enabling app lock.")) }
            .onChange(of: preferences.reminderOffsets) { _, offsets in
                if !offsets.isEmpty { Task { await requestPermissionIfNeeded() } }
            }
            .onChange(of: preferences.dailySummary) { _, enabled in
                if enabled { Task { await requestPermissionIfNeeded() } }
            }
    }

    private var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0" }
    private var customOffsetValue: Int? {
        let normalized = customOffset.trimmingCharacters(in: .whitespacesAndNewlines).map { character in
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return character }
            return Character(String(digit))
        }
        return Int(String(normalized))
    }
    private var timeBinding: Binding<Date> {
        Binding(get: {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = app.preferences.reminderHour
            components.minute = app.preferences.reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }, set: { date in
            app.preferences.reminderHour = Calendar.current.component(.hour, from: date)
            app.preferences.reminderMinute = Calendar.current.component(.minute, from: date)
        })
    }
    private func requestPermissionIfNeeded() async {
        guard records.contains(where: { $0.isActive && $0.remindersEnabled && $0.snapshot.isOutstanding }) else { return }
        await app.notifications.refreshAuthorization()
        if app.notifications.authorizationStatus == .notDetermined {
            await app.notifications.requestPermission()
            app.didMutate()
        }
    }
    private func reminderToggle(_ title: String, offset: Int) -> some View {
        Toggle(app.tr(title), isOn: Binding(get: { app.preferences.reminderOffsets.contains(offset) }, set: { enabled in
            var offsets = app.preferences.reminderOffsets.filter { $0 != offset }
            if enabled { offsets.append(offset) }
            app.preferences.reminderOffsets = offsets.sorted(by: >)
        }))
    }
    @ViewBuilder private var notificationPermission: some View {
        switch app.notifications.authorizationStatus {
        case .notDetermined:
            Button(app.tr("Enable notifications")) {
                Task { await app.notifications.requestPermission(); app.didMutate() }
            }
        case .denied:
            Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                Label(app.tr("Enable in iPhone Settings"), systemImage: "bell.slash")
            }
        default:
            Label(app.tr("Notifications enabled"), systemImage: "bell.badge.fill").foregroundStyle(Theme.accent)
        }
    }
    private var syncLabel: String {
        switch app.sync.state {
        case .checking: return app.tr("Checking iCloud")
        case .available: return app.tr("iCloud available")
        case .syncing: return app.tr("Syncing")
        case .synced: return app.tr("Synced")
        case .offline: return app.tr("Offline — saved on this iPhone")
        case .unavailable: return app.tr("Sign in to iCloud to sync")
        case .failed: return app.tr("Sync paused — records remain on this iPhone")
        case .localOnly:
            #if targetEnvironment(simulator)
            return app.tr("Simulator — local storage")
            #else
            return app.tr("Local storage — restart to retry iCloud")
            #endif
        }
    }
    private var syncSymbol: String {
        switch app.sync.state {
        case .synced, .available: return "icloud.fill"
        case .syncing, .checking: return "arrow.triangle.2.circlepath"
        default: return "icloud.slash"
        }
    }
}

@MainActor
private struct PrivacyPolicyView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                policy("Your records", "Cheque details and photos are stored on this iPhone. When iCloud is available, they sync to your private Apple account.")
                policy("Camera and text recognition", "The camera is used only when you choose to scan. Text recognition happens on this iPhone. No cheque photo is sent to an external recognition service.")
                policy("Notifications", "Reminders are scheduled on this device. You control permission, timing and whether cheque details appear in alerts.")
                policy("App lock", "Authentication is handled by iOS. Shekati does not access or store your biometric information or device passcode.")
                policy("Your control", "Deleted cheques can be restored for 30 days. Permanent deletion also syncs to iCloud. You can create an independent password-protected backup. CSV and PDF exports contain readable details; share them only when you choose.")
                policy("Analytics", "Shekati includes no advertising or third-party analytics SDK. Apple may provide store and crash diagnostics according to your Apple settings.")
            }.padding(24)
        }.navigationTitle(app.tr("Privacy policy")).background(Theme.background)
    }
    private func policy(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.tr(title)).font(.headline)
            Text(app.tr(text)).foregroundStyle(.secondary)
        }
    }
}
