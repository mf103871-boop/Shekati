import SwiftUI
import SwiftData

@main
@MainActor
struct ShekatiApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    @State private var state: AppState
    @StateObject private var plus = ShekatiPlusStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        var built: ModelContainer?
        var fallbackReason: String?
        var failure: String?
        let isUITesting = CommandLine.arguments.contains("--ui-testing")
        if isUITesting {
            let memory = ModelConfiguration("UITests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do { built = try ModelContainer(for: schema, configurations: [memory]) }
            catch { failure = error.localizedDescription }
            container = built
            startupError = failure
            let testDefaults = UserDefaults(suiteName: "com.shekati.ui-testing")!
            testDefaults.removePersistentDomain(forName: "com.shekati.ui-testing")
            let requestedLocale = UserDefaults.standard.string(forKey: "ShekatiStoreLocale")
            testDefaults.set(requestedLocale ?? (CommandLine.arguments.contains("--arabic") ? "ar" : "en"), forKey: "language")
            testDefaults.set([Int](), forKey: "reminderOffsets")
            let appState = AppState(localOnlyReason: "UI test storage", defaults: testDefaults)
            if let built {
                #if DEBUG && targetEnvironment(simulator)
                if CommandLine.arguments.contains("--store-screens") {
                    do { try StoreScreenshotFixtures.seedIfRequested(in: built, language: appState.preferences.language) }
                    catch { assertionFailure("Screenshot fixtures failed: \(error)") }
                    appState.today = StoreScreenshotFixtures.referenceDay
                } else if CommandLine.arguments.contains("--legacy-settlement-test") {
                    do { try StoreScreenshotFixtures.seedLegacySettlement(in: built) }
                    catch { assertionFailure("Legacy settlement fixture failed: \(error)") }
                }
                #endif
                appState.configureNotificationContext(container: built)
            }
            _state = State(initialValue: appState)
            return
        }
        #if targetEnvironment(simulator)
        let isSimulator = true
        fallbackReason = "Simulator builds use local storage. Verify iCloud with a signed iPhone build."
        #else
        let isSimulator = false
        #endif
        do {
            let directory = URL.applicationSupportDirectory.appending(path: "Shekati", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "Shekati.store")
            let cloud = ModelConfiguration("Shekati", schema: schema, url: url,
                                           cloudKitDatabase: isSimulator ? .none : .automatic)
            do { built = try ModelContainer(for: schema, configurations: [cloud]) }
            catch {
                fallbackReason = error.localizedDescription
                let local = ModelConfiguration("Shekati", schema: schema, url: url, cloudKitDatabase: .none)
                built = try ModelContainer(for: schema, configurations: [local])
            }
        } catch { failure = error.localizedDescription }
        container = built
        startupError = failure
        let appState = AppState(localOnlyReason: fallbackReason)
        if let built { appState.configureNotificationContext(container: built) }
        _state = State(initialValue: appState)
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .environment(state)
                    .environmentObject(plus)
                    .task(id: scenePhase) {
                        if scenePhase == .active { await plus.refreshEntitlement() }
                    }
                    .environment(\.locale, state.preferences.language.locale)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                    .environment(\.layoutDirection, state.preferences.language.isRTL ? .rightToLeft : .leftToRight)
                    .preferredColorScheme(state.preferences.appearance == .system ? nil :
                                          state.preferences.appearance == .dark ? .dark : .light)
                    .tint(Theme.accent)
            } else {
                ContentUnavailableView {
                    Label(state.tr("Unable to open your records"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(state.tr("Your saved files were preserved. Restart the app and contact support if this continues."))
                    if let startupError { Text(startupError).font(.footnote) }
                }
            }
        }
    }
}
