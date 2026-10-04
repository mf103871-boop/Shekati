import Foundation
import Observation
import UserNotifications
import ShekatiCore

@MainActor @Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    private(set) var firstUncoveredDate: Date?
    private(set) var message: String?
    private(set) var nextReminderDates: [UUID: Date] = [:]
    private(set) var pendingOpenChequeID: UUID?
    var onOpenCheque: ((UUID) -> Void)? {
        didSet { if let id = pendingOpenChequeID { onOpenCheque?(id) } }
    }
    var isDenied: Bool { authorizationStatus == .denied }

    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var permissionOperation: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var languageCode = "ar"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var snoozed: [SnoozedCheque]
    @ObservationIgnored var contextProvider: (() -> ReminderContext?)?
    private static let snoozeStorageKey = "snoozedCheques.v1"

    override convenience init() { self.init(center: .current(), defaults: .standard) }
    convenience init(defaults: UserDefaults) { self.init(center: .current(), defaults: defaults) }

    init(center: UNUserNotificationCenter, defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        self.snoozed = defaults.data(forKey: Self.snoozeStorageKey)
            .flatMap { try? JSONDecoder().decode([SnoozedCheque].self, from: $0) } ?? []
        super.init()
        center.delegate = self
    }

    func acknowledgeOpenCheque(_ id: UUID) {
        if pendingOpenChequeID == id { pendingOpenChequeID = nil }
        Task {
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
                $0.request.identifier.hasPrefix(ReminderPlanner.identifierPrefix) &&
                $0.request.content.userInfo["chequeID"] as? String == id.uuidString
            }.map { $0.request.identifier })
        }
    }

    func nextReminderDate(for id: UUID) -> Date? {
        guard let date = nextReminderDates[id], date > Date() else { return nil }
        return date
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        if let permissionOperation { await permissionOperation.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do { _ = try await self.center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch { self.message = self.localized("تعذر تفعيل التنبيهات. حاول مرة أخرى من الإعدادات.", "Notifications could not be enabled. Try again in Settings.") }
            await self.refreshAuthorization()
        }
        permissionOperation = task
        await task.value
        permissionOperation = nil
    }

    func reschedule(inputs: [ChequeReminderInput], settings: ReminderSettings, now: Date = Date()) async {
        revision &+= 1
        let currentRevision = revision
        let previous = operation
        let next = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.revision == currentRevision else { return }
            await self.performReschedule(inputs: inputs, settings: settings, now: now, revision: currentRevision)
        }
        operation = next
        await next.value
    }

    private func performReschedule(inputs: [ChequeReminderInput], settings: ReminderSettings,
                                   now: Date, revision currentRevision: Int) async {
        languageCode = settings.languageCode
        await refreshAuthorization()
        guard revision == currentRevision else { return }
        registerCategories(languageCode: settings.languageCode)
        let active = Dictionary(inputs.filter { $0.enabled && $0.snapshot.isOutstanding }.map { ($0.snapshot.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        snoozed = snoozed.filter { entry in
            entry.fireDate > now && active[entry.chequeID]?.snapshot.dueDate.iso == entry.dueDateISO
        }
        persistSnoozes()
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now, snoozed: snoozed)
        let old = await center.pendingNotificationRequests()
        guard revision == currentRevision else { return }
        let hasPermission = authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
        let wantedIDs = Set(plan.items.map(\.id))
        let obsoleteIDs = old.map(\.identifier).filter {
            $0.hasPrefix(ReminderPlanner.identifierPrefix) && (!hasPermission || !wantedIDs.contains($0))
        }
        // Keep unchanged identifiers alive while updating the queue. Adding the same identifier replaces it.
        // Removing obsolete identifiers first also prevents temporary growth beyond the bounded queue.
        center.removePendingNotificationRequests(withIdentifiers: obsoleteIDs)
        let delivered = await center.deliveredNotifications()
        guard revision == currentRevision else { return }
        let staleDelivered = delivered.filter { notification in
            let request = notification.request
            return request.identifier.hasPrefix(ReminderPlanner.identifierPrefix) &&
                (!hasPermission || !ReminderRequestPolicy.isCurrentDelivered(identifier: request.identifier,
                    title: request.content.title, body: request.content.body,
                    signature: request.content.userInfo["signature"] as? String,
                    inputs: inputs, settings: settings, hasCoverageNotice: wantedIDs.contains("shekati.coverage")))
        }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered)

        guard hasPermission else {
            scheduledCount = 0
            nextReminderDates = [:]
            firstUncoveredDate = plan.items.first?.fireDate
            message = plan.items.isEmpty ? nil : localized("فعّل التنبيهات حتى تصلك تذكيرات الشيكات.", "Enable notifications to receive cheque reminders.")
            return
        }
        var failedDate: Date?
        let oldByID = Dictionary(old.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for item in plan.items {
            guard revision == currentRevision else { return }
            let input = item.chequeID.flatMap { active[$0] }
            let signature = input.map { ReminderRequestPolicy.signature(input: $0, settings: settings) }
            if let existing = oldByID[item.id], ReminderRequestPolicy.matches(existing, item: item, signature: signature) { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.chequeID.map { "cheque.\($0.uuidString)" } ?? "cheque.overview"
            content.userInfo = ["kind": item.kind.rawValue, "requestedFireDate": item.fireDate.timeIntervalSince1970]
            if let id = item.chequeID {
                content.userInfo["chequeID"] = id.uuidString
                content.categoryIdentifier = ReminderRequestPolicy.chequeCategory
                if let signature { content.userInfo["signature"] = signature }
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            components.calendar = calendar
            // Keep Gregorian civil dates even with a Hijri system calendar; let the device choose its local zone.
            // Reverify after travel when the app becomes active; closed-app travel behavior needs device testing.
            components.timeZone = nil
            let trigger: UNNotificationTrigger
            if item.kind == .snooze || (item.kind == .replenishment && item.fireDate.timeIntervalSinceNow < 60) {
                // Calendar components have whole-second precision; an imminent coverage notice needs a short interval.
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.01, item.fireDate.timeIntervalSinceNow), repeats: false)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            do { try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)) }
            catch {
                failedDate = ReminderPlanner.earliest(failedDate, item.fireDate)
                // A failed replacement must not leave an old date or newly hidden private text in the queue.
                center.removePendingNotificationRequests(withIdentifiers: [item.id])
            }
        }
        guard revision == currentRevision else { return }
        let actual = await center.pendingNotificationRequests()
        guard revision == currentRevision else { return }
        let accepted = Dictionary(actual.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let justDelivered = await center.deliveredNotifications()
        guard revision == currentRevision else { return }
        let deliveredRequests = Dictionary(justDelivered.filter { $0.date >= now }.map { ($0.request.identifier, $0.request) },
                                           uniquingKeysWith: { first, _ in first })
        var acceptedDates: [String: Date] = [:]
        for item in plan.items {
            let request = accepted[item.id]
            let signature = item.chequeID.flatMap { active[$0] }.map { ReminderRequestPolicy.signature(input: $0, settings: settings) }
            let contentMatches = request.map { ReminderRequestPolicy.matches($0, item: item, signature: signature) } ?? false
            if contentMatches, let trigger = request?.trigger as? UNCalendarNotificationTrigger, let nextDate = trigger.nextTriggerDate() {
                acceptedDates[item.id] = nextDate
            } else if contentMatches, let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger,
                      let nextDate = trigger.nextTriggerDate() {
                acceptedDates[item.id] = nextDate
            } else if let delivered = deliveredRequests[item.id], delivered.content.title == item.title, delivered.content.body == item.body,
                      item.chequeID == nil || delivered.content.userInfo["signature"] as? String == signature {
                // An imminent notice may already have fired, which is successful acceptance rather than a missing alert.
                if let trigger = delivered.trigger as? UNCalendarNotificationTrigger,
                   let originalDate = trigger.dateComponents.date {
                    acceptedDates[item.id] = originalDate
                } else if let trigger = delivered.trigger as? UNTimeIntervalNotificationTrigger {
                    if let date = trigger.nextTriggerDate() { acceptedDates[item.id] = date }
                    else if item.kind == .replenishment,
                            let requested = delivered.content.userInfo["requestedFireDate"] as? Double,
                            abs(requested - item.fireDate.timeIntervalSince1970) < 0.001 {
                        // This exact immediate coverage notice was delivered during this operation.
                        // Delivery may be delayed by iOS; it counts as a received warning, never future coverage.
                        acceptedDates[item.id] = item.fireDate
                    }
                }
            }
        }
        let confirmation = ReminderPlanner.confirm(plan: plan, acceptedDates: acceptedDates)
        let incorrectIDs = plan.items.filter { item in
            guard let date = acceptedDates[item.id] else { return true }
            return abs(date.timeIntervalSince(item.fireDate)) >= 1
        }.map(\.id)
        // A request accepted for a different time is not useful coverage and must not fire as a stale reminder.
        center.removePendingNotificationRequests(withIdentifiers: incorrectIDs)
        center.removeDeliveredNotifications(withIdentifiers: incorrectIDs)
        scheduledCount = plan.items.filter { item in
            accepted[item.id] != nil && acceptedDates[item.id].map { $0 > Date() && abs($0.timeIntervalSince(item.fireDate)) < 1 } == true
        }.count
        var dates: [UUID: Date] = [:]
        for item in plan.items {
            guard let id = item.chequeID, let date = acceptedDates[item.id], date > Date(),
                  abs(date.timeIntervalSince(item.fireDate)) < 1, accepted[item.id] != nil else { continue }
            dates[id] = ReminderPlanner.earliest(dates[id], date)
        }
        nextReminderDates = dates
        firstUncoveredDate = ReminderPlanner.earliest(confirmation.firstUncoveredDate, failedDate)
        if failedDate != nil || confirmation.acceptedCount != plan.items.count {
            message = localized("بعض التذكيرات لم تُجدول. افتح إعدادات التنبيهات وحاول التحديث.", "Some reminders could not be scheduled. Check notification settings and refresh.")
        } else if firstUncoveredDate != nil {
            message = localized("التذكيرات جاهزة لفترة محدودة. افتح التطبيق قبل نهاية التغطية لتجهيز البقية.", "Reminders cover a limited period. Open the app before coverage ends to prepare the rest.")
        } else if authorizationStatus == .provisional && !plan.items.isEmpty {
            message = localized("التنبيهات الحالية تظهر بصمت. يمكنك تفعيل الصوت من إعدادات الآيفون.", "Notifications currently arrive quietly. Enable alerts and sound in iPhone Settings.")
        } else { message = nil }
    }

    private func localized(_ arabic: String, _ english: String) -> String { languageCode.hasPrefix("ar") ? arabic : english }

    private func registerCategories(languageCode: String) {
        let title = languageCode.hasPrefix("ar") ? "ذكّرني بعد ساعة" : "Remind me in 1 hour"
        let snooze = UNNotificationAction(identifier: ReminderRequestPolicy.snoozeAction, title: title,
                                          options: [.authenticationRequired])
        center.setNotificationCategories([UNNotificationCategory(identifier: ReminderRequestPolicy.chequeCategory,
                                                                 actions: [snooze], intentIdentifiers: [], options: [])])
    }

    private func persistSnoozes() {
        if let data = try? JSONEncoder().encode(snoozed) { defaults.set(data, forKey: Self.snoozeStorageKey) }
    }

    private func snooze(_ request: UNNotificationRequest, chequeID id: UUID) async {
        guard let context = contextProvider?(),
              let input = context.inputs.first(where: { $0.snapshot.id == id }), input.enabled, input.snapshot.isOutstanding,
              ReminderRequestPolicy.isCurrentDelivered(identifier: request.identifier, title: request.content.title,
                  body: request.content.body, signature: request.content.userInfo["signature"] as? String,
                  inputs: context.inputs, settings: context.settings, hasCoverageNotice: false) else { return }
        // Store only identity, civil due date and requested time; content is rebuilt from current records and privacy settings.
        let date = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3_600).rounded(.up))
        snoozed.removeAll { $0.chequeID == id }
        snoozed.append(SnoozedCheque(chequeID: id, fireDate: date, dueDateISO: input.snapshot.dueDate.iso))
        persistSnoozes()
        await reschedule(inputs: context.inputs, settings: context.settings)
        let requests = await center.pendingNotificationRequests()
        if requests.contains(where: { $0.identifier == "shekati.snooze.\(id.uuidString)" &&
            ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate().map { abs($0.timeIntervalSince(date)) < 1 } == true }) {
            center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["chequeID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            if let id, let self {
                if response.actionIdentifier == ReminderRequestPolicy.snoozeAction {
                    await self.snooze(response.notification.request, chequeID: id)
                } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                    self.pendingOpenChequeID = id
                    self.onOpenCheque?(id)
                }
            }
            completionHandler()
        }
    }
}
