import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [ChequeRecord]
    @Query(sort: \AppConfiguration.createdAt) private var configurations: [AppConfiguration]
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var selectedTab = 0
    @State private var addingCheque = false
    /// A deep link keeps only the identifier. The record is resolved from the live query when the
    /// sheet renders, so a cheque purged while the sheet is open is never read.
    private struct LinkedCheque: Identifiable { let id: UUID }
    @State private var linkedCheque: LinkedCheque?
    @State private var dayRevision = 0

    private var reminderSignature: [[String]] {
        let inputs = records.filter { $0.deletedAt == nil }.map {
            ChequeReminderInput(snapshot: $0.snapshot, enabled: $0.remindersEnabled,
                                offsets: $0.reminderOffsets, hour: $0.reminderHour, minute: $0.reminderMinute)
        }
        return ReminderRequestPolicy.refreshKey(inputs: inputs, settings: app.reminderSettings,
            dayRevision: dayRevision, authorizationStatus: app.notifications.authorizationStatus.rawValue,
            mutationRevision: app.revision)
    }

    private var currencySignature: String {
        configurations.map { "\($0.id):\($0.currencyCode)" }.joined(separator: ";") +
            "|" + Set(records.map(\.currencyCode)).sorted().joined(separator: ";")
    }

    var body: some View {
        ZStack {
            Group {
                if app.currencyCode.isEmpty && records.isEmpty {
                    CurrencySetupView()
                } else {
                    TabView(selection: Binding(get: { selectedTab }, set: { tab in
                        if tab == 2 { addingCheque = true } else { selectedTab = tab }
                    })) {
                        NavigationStack {
                            DashboardView()
                        }.tabItem { Label(app.tr("Home"), systemImage: "house") }.tag(0)
                        NavigationStack {
                            ChequeListView()
                        }.tabItem { Label(app.tr("Cheques"), systemImage: "list.bullet.rectangle") }.tag(1)
                        Color.clear.tabItem { Label(app.tr("Add"), systemImage: "plus.circle.fill") }.tag(2)
                        NavigationStack { DueCalendarView() }
                            .tabItem { Label(app.tr("Calendar"), systemImage: "calendar") }.tag(3)
                        NavigationStack { ShekatiMoreView() }
                            .tabItem { Label(app.tr("More"), systemImage: "ellipsis") }.tag(4)
                    }
                }
            }
            .disabled(app.lock.isLocked)
            .accessibilityHidden(app.lock.isLocked)
            if app.lock.isLocked { lockScreen }
            if scenePhase != .active && (app.preferences.appLockEnabled || hidesAmounts) {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) { BrandMark(); Text(app.tr("Shekati")).font(.title.bold()) }
            }
        }
        .sheet(isPresented: $addingCheque) {
            NavigationStack { ChequeEditorView() }
        }
        .sheet(item: $linkedCheque, onDismiss: {
            if let id = app.openedChequeID { app.notifications.acknowledgeOpenCheque(id) }
            app.openedChequeID = nil
        }) { item in
            NavigationStack {
                Group {
                    if let record = records.first(where: { $0.id == item.id }) {
                        ChequeDetailView(record: record)
                    } else {
                        ContentUnavailableView(app.tr("This cheque is no longer available"), systemImage: "trash.slash",
                                               description: Text(app.tr("It was permanently deleted, possibly from another device.")))
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(app.tr("Done")) { linkedCheque = nil }
                } }
            }
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, app.preferences.language.isRTL ? .rightToLeft : .leftToRight)
        }
        .task(id: currencySignature) { reconcileCurrency() }
        .task(id: reminderSignature) {
            let inputs = records.filter { $0.deletedAt == nil }.map { ChequeReminderInput(snapshot: $0.snapshot,
                                      enabled: $0.remindersEnabled, offsets: $0.reminderOffsets,
                                      hour: $0.reminderHour, minute: $0.reminderMinute) }
            await app.notifications.reschedule(inputs: inputs, settings: app.reminderSettings)
        }
        .task {
            app.lock.synchronize(enabled: app.preferences.appLockEnabled)
            app.privacy.update(app: app, phase: scenePhase)
            await app.notifications.refreshAuthorization()
            await app.sync.refresh()
            presentPendingLink()
        }
        .onChange(of: app.preferences.appLockEnabled) { _, value in
            app.lock.synchronize(enabled: value)
            app.privacy.update(app: app, phase: scenePhase)
        }
        .onChange(of: hidesAmounts) { _, _ in app.didMutate() }
        .onChange(of: app.preferences.language) { _, language in app.lock.languageCode = language.rawValue }
        .onChange(of: app.openedChequeID) { _, _ in presentPendingLink() }
        .onChange(of: app.lock.isLocked) { _, locked in
            app.privacy.update(app: app, phase: scenePhase)
            if !locked { presentPendingLink() }
        }
        .onChange(of: records.map(\.id)) { _, _ in presentPendingLink() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && app.preferences.appLockEnabled { app.lock.lock() }
            app.privacy.update(app: app, phase: phase)
            if phase == .active {
                app.today = .today
                dayRevision &+= 1
                Task { await app.notifications.refreshAuthorization(); await app.sync.refresh() }
                presentPendingLink()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            app.privacy.update(app: app, phase: .inactive)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if app.preferences.appLockEnabled { app.lock.lock() }
            app.privacy.update(app: app, phase: .background)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            app.privacy.update(app: app, phase: .active)
        }
    }

    private var lockScreen: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 24) {
            BrandMark()
            Text(app.tr("Your cheques, protected")).font(.title2.bold()).multilineTextAlignment(.center)
            Text(app.tr("Unlock to view your records")).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Task { await app.lock.unlock() }
            } label: {
                Label(app.tr("Unlock"), systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).disabled(app.lock.isAuthenticating)
            if app.lock.errorMessage != nil {
                Text(app.tr("Could not unlock. Try again using biometrics or your device passcode."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(32).frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        }
            .background(Theme.background.ignoresSafeArea())
    }

    private func presentPendingLink() {
        guard !app.lock.isLocked, scenePhase == .active, let id = app.openedChequeID else { return }
        if records.contains(where: { $0.id == id }) { linkedCheque = LinkedCheque(id: id) }
        else {
            // A link can arrive before the CloudKit import. Keep it until records arrive.
            selectedTab = 1
        }
    }

    private func refreshDay() {
        app.today = .today
        dayRevision &+= 1
    }

    private func reconcileCurrency() {
        let currencies = Set(records.map(\.currencyCode).filter { !$0.isEmpty })
        // A cheque retains its currency. The configuration is only the default for new records.
        app.currencyConflict = currencies.count > 1
        app.currencyCode = configurations.first?.currencyCode ?? currencies.sorted().first ?? ""
    }
}
