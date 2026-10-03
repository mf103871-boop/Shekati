import Foundation
import Observation
import ShekatiCore

@MainActor @Observable
final class AppState {
    let preferences: UserPreferences
    let notifications: NotificationService
    let sync: SyncMonitor
    let lock: AppLockController
    let privacy = PrivacyShield()
    var currencyCode = ""
    var currencyConflict = false
    var revision: Int = 0
    var today: LocalDay = .today
    var openedChequeID: UUID?
    var persistenceMessage: String?

    init(localOnlyReason: String? = nil, defaults: UserDefaults = .standard) {
        preferences = UserPreferences(defaults: defaults)
        notifications = NotificationService()
        sync = SyncMonitor(localOnlyReason: localOnlyReason)
        lock = AppLockController()
        lock.languageCode = preferences.language.rawValue
        lock.synchronize(enabled: preferences.appLockEnabled)
        notifications.onOpenCheque = { [weak self] id in self?.openedChequeID = id }
    }

    func didMutate() { revision &+= 1 }
    func tr(_ key: String) -> String { preferences.tr(key) }
    func formatAmount(_ minor: Int64) -> String {
        CurrencyMath.format(minorUnits: minor, currencyCode: currencyCode, locale: preferences.language.locale)
    }
    func formatDay(_ day: LocalDay) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = preferences.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day.date())
    }
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = preferences.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
