import Foundation
import Observation
import ShekatiCore
import SwiftData

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
        notifications = NotificationService(defaults: defaults)
        sync = SyncMonitor(localOnlyReason: localOnlyReason)
        lock = AppLockController()
        lock.languageCode = preferences.language.rawValue
        lock.synchronize(enabled: preferences.appLockEnabled)
        notifications.onOpenCheque = { [weak self] id in self?.openedChequeID = id }
    }

    func didMutate() { revision &+= 1 }
    func tr(_ key: String) -> String { preferences.tr(key) }
    func formatAmount(_ minor: Int64) -> String {
        DisplayFormatting.amount(minorUnits: minor, currencyCode: currencyCode, locale: preferences.language.locale)
    }
    func formatDay(_ day: LocalDay) -> String {
        DisplayFormatting.day(day, locale: preferences.language.locale)
    }
    func formatTimestamp(_ date: Date) -> String {
        DisplayFormatting.timestamp(date, locale: preferences.language.locale)
    }

    func relativeDueDate(_ day: LocalDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let distance = calendar.dateComponents([.day], from: today.date(calendar: calendar), to: day.date(calendar: calendar)).day ?? 0
        if distance == 0 { return tr("Today") }
        if distance == 1 { return tr("Tomorrow") }
        if distance == -1 { return tr("Overdue by 1 day") }
        if distance == -2 { return tr("Overdue by 2 days") }
        if distance == 2 { return tr("In 2 days") }
        if distance < 0 { return String(format: tr("Overdue by %d days"), -distance) }
        return String(format: tr("In %d days"), distance)
    }

    func configureNotificationContext(container: ModelContainer) {
        notifications.contextProvider = { [weak self] in
            guard let self else { return nil }
            do {
                let records = try container.mainContext.fetch(FetchDescriptor<ChequeRecord>())
                return ReminderContext(inputs: records.filter { $0.deletedAt == nil }.map {
                    ChequeReminderInput(snapshot: $0.snapshot, enabled: $0.remindersEnabled,
                                        offsets: $0.reminderOffsets, hour: $0.reminderHour, minute: $0.reminderMinute)
                }, settings: self.reminderSettings)
            } catch { return nil }
        }
    }

    var reminderSettings: ReminderSettings {
        ReminderSettings(offsets: preferences.reminderOffsets, hour: preferences.reminderHour,
                         minute: preferences.reminderMinute, dailySummary: preferences.dailySummary,
                         hideDetails: preferences.hideNotificationDetails, languageCode: preferences.language.rawValue)
    }

    func requestNotificationPermissionIfNeeded() async {
        await notifications.refreshAuthorization()
        guard notifications.authorizationStatus == .notDetermined,
              let context = notifications.contextProvider?(),
              !ReminderPlanner.makePlan(inputs: context.inputs, settings: context.settings).items.isEmpty else { return }
        await notifications.requestPermission()
    }
}
