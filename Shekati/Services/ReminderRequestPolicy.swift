import CryptoKit
import Foundation
import UserNotifications
import ShekatiCore

enum ReminderRequestPolicy {
    static let chequeCategory = "SHEKATI_CHEQUE"
    static let snoozeAction = "SHEKATI_SNOOZE_HOUR"

    /// Structural identity for the view's refresh task. Each field is a separate
    /// array element, so user text containing separators cannot hide a change.
    /// No per-record hashing or money formatting runs while deriving this key.
    static func refreshKey(inputs: [ChequeReminderInput], settings: ReminderSettings,
                           dayRevision: Int, authorizationStatus: Int) -> [[String]] {
        let global = [String(dayRevision), String(authorizationStatus), settings.languageCode,
                      String(settings.hour), String(settings.minute), String(settings.dailySummary),
                      String(settings.hideDetails), String(settings.offsets.count)] +
            settings.offsets.sorted().map(String.init)
        let records = inputs.sorted { $0.snapshot.id.uuidString < $1.snapshot.id.uuidString }.map { input in
            let cheque = input.snapshot
            let offsets = input.offsets ?? []
            return [cheque.id.uuidString, cheque.direction.rawValue, cheque.status.rawValue,
                    cheque.dueDate.iso, String(cheque.amountMinorUnits), cheque.currencyCode,
                    cheque.number, cheque.party, String(input.enabled),
                    input.offsets == nil ? "default" : "custom", String(offsets.count),
                    input.hour.map(String.init) ?? "default", input.minute.map(String.init) ?? "default"] +
                offsets.sorted().map(String.init)
        }
        return [global] + records
    }

    /// This fingerprint contains no plaintext cheque information and ignores notes, photos and ordering.
    static func signature(input: ChequeReminderInput, settings: ReminderSettings) -> String {
        let cheque = input.snapshot
        let fields = [cheque.id.uuidString, cheque.direction.rawValue, cheque.status.rawValue,
                      cheque.dueDate.iso, String(cheque.amountMinorUnits), cheque.currencyCode, cheque.number, cheque.party,
                      String(input.enabled), (input.offsets ?? settings.offsets).sorted().map(String.init).joined(separator: ","),
                      String(input.hour ?? settings.hour), String(input.minute ?? settings.minute),
                      String(settings.hideDetails), settings.languageCode]
        let data = (try? JSONEncoder().encode(fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matches(_ request: UNNotificationRequest, item: PlannedReminder, signature: String?) -> Bool {
        guard request.identifier == item.id, request.content.title == item.title, request.content.body == item.body,
              request.content.userInfo["kind"] as? String == item.kind.rawValue,
              request.content.sound != nil else { return false }
        if let id = item.chequeID {
            guard request.content.categoryIdentifier == chequeCategory,
                  request.content.userInfo["chequeID"] as? String == id.uuidString,
                  request.content.userInfo["signature"] as? String == signature else { return false }
        }
        if let trigger = request.trigger as? UNCalendarNotificationTrigger,
           let date = trigger.nextTriggerDate() {
            return !trigger.repeats && abs(date.timeIntervalSince(item.fireDate)) < 1
        }
        if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
           (item.kind == .snooze || item.kind == .replenishment), let date = trigger.nextTriggerDate() {
            return !trigger.repeats && abs(date.timeIntervalSince(item.fireDate)) < 1
        }
        return false
    }

    /// Retain an unanswered alert while its cheque and displayed details remain valid.
    static func isCurrentDelivered(identifier: String, title: String, body: String, signature: String?,
                                   inputs: [ChequeReminderInput], settings: ReminderSettings,
                                   hasCoverageNotice: Bool, calendar supplied: Calendar = .current) -> Bool {
        let parts = identifier.split(separator: ".").map(String.init)
        guard parts.count >= 2, parts[0] == "shekati" else { return true }
        let active = inputs.filter { $0.enabled && $0.snapshot.isOutstanding }
        switch parts[1] {
        case "cheque", "snooze":
            guard parts.count >= 3, let id = UUID(uuidString: parts[2]),
                  let input = active.first(where: { $0.snapshot.id == id }) else { return false }
            if let signature, signature != Self.signature(input: input, settings: settings) { return false }
            // A legacy hidden alert has no date in its text and no fingerprint; its validity cannot be proven.
            if signature == nil && settings.hideDetails { return false }
            let offset: Int?
            if parts[1] == "cheque" {
                guard parts.count == 4, let value = Int(parts[3]), (input.offsets ?? settings.offsets).contains(value) else { return false }
                offset = value
            } else { offset = nil }
            let expected = ReminderPlanner.chequeContent(cheque: input.snapshot, settings: settings, offset: offset)
            return expected.title == title && expected.body == body
        case "summary":
            guard settings.dailySummary, parts.count == 3, let day = LocalDay(iso: parts[2]) else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = supplied.timeZone
            let expected = ReminderPlanner.makeSummary(day: day, date: day.date(calendar: calendar),
                                                       inputs: active, settings: settings, calendar: calendar)
            return expected?.title == title && expected?.body == body
        case "coverage": return hasCoverageNotice
        default: return false
        }
    }
}
