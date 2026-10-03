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
    private(set) var pendingOpenChequeID: UUID?
    var onOpenCheque: ((UUID) -> Void)? {
        didSet { if let id = pendingOpenChequeID { onOpenCheque?(id) } }
    }
    var isDenied: Bool { authorizationStatus == .denied }

    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var languageCode = "ar"

    override convenience init() { self.init(center: .current()) }

    init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func acknowledgeOpenCheque(_ id: UUID) {
        if pendingOpenChequeID == id { pendingOpenChequeID = nil }
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { message = localized("تعذر تفعيل التنبيهات. حاول مرة أخرى من الإعدادات.", "Notifications could not be enabled. Try again in Settings.") }
        await refreshAuthorization()
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
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now)
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
        // Opening/editing the app acknowledges old managed alerts; no stale settled/edited cheque remains visible.
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) })

        guard hasPermission else {
            scheduledCount = 0
            firstUncoveredDate = plan.items.first?.fireDate
            message = plan.items.isEmpty ? nil : localized("فعّل التنبيهات حتى تصلك تذكيرات الشيكات.", "Enable notifications to receive cheque reminders.")
            return
        }
        var failedDate: Date?
        for item in plan.items {
            guard revision == currentRevision else { return }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.chequeID.map { "cheque.\($0.uuidString)" } ?? "cheque.overview"
            content.userInfo = ["kind": item.kind.rawValue]
            if let id = item.chequeID { content.userInfo["chequeID"] = id.uuidString }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            components.calendar = calendar
            // Keep Gregorian civil dates even with a Hijri system calendar; let the device choose its local zone.
            // Reverify after travel when the app becomes active; closed-app travel behavior needs device testing.
            components.timeZone = nil
            let trigger: UNNotificationTrigger
            if item.kind == .replenishment && item.fireDate.timeIntervalSinceNow < 60 {
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
            let contentMatches = request?.content.title == item.title && request?.content.body == item.body
            if contentMatches, let trigger = request?.trigger as? UNCalendarNotificationTrigger, let nextDate = trigger.nextTriggerDate() {
                acceptedDates[item.id] = nextDate
            } else if contentMatches && item.kind == .replenishment && request?.trigger is UNTimeIntervalNotificationTrigger {
                acceptedDates[item.id] = item.fireDate
            } else if let delivered = deliveredRequests[item.id], delivered.content.title == item.title, delivered.content.body == item.body {
                // An imminent notice may already have fired, which is successful acceptance rather than a missing alert.
                if let trigger = delivered.trigger as? UNCalendarNotificationTrigger,
                   let originalDate = trigger.dateComponents.date {
                    acceptedDates[item.id] = originalDate
                } else if item.kind == .replenishment && delivered.trigger is UNTimeIntervalNotificationTrigger {
                    acceptedDates[item.id] = item.fireDate
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
        scheduledCount = confirmation.acceptedCount
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

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["chequeID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            if let id, let self {
                self.pendingOpenChequeID = id
                self.onOpenCheque?(id)
            }
            completionHandler()
        }
    }
}
