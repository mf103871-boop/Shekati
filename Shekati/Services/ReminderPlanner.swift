import Foundation
import ShekatiCore

struct ReminderSettings: Equatable, Sendable {
    var offsets: [Int]
    var hour: Int
    var minute: Int
    var dailySummary: Bool
    var hideDetails: Bool
    var languageCode: String
    var bankingCalendar: BankingCalendar? = nil
}

struct ChequeReminderInput: Sendable {
    var snapshot: ChequeSnapshot
    var enabled: Bool
    var offsets: [Int]?
    var hour: Int?
    var minute: Int?

    init(snapshot: ChequeSnapshot, enabled: Bool, offsets: [Int]?, hour: Int? = nil, minute: Int? = nil) {
        self.snapshot = snapshot
        self.enabled = enabled
        self.offsets = offsets
        self.hour = hour
        self.minute = minute
    }
}

enum ReminderKind: String, Sendable { case cheque, snooze, dailySummary, replenishment }

struct ReminderContext: Sendable {
    var inputs: [ChequeReminderInput]
    var settings: ReminderSettings
}

struct SnoozedCheque: Codable, Equatable, Sendable {
    var chequeID: UUID
    var fireDate: Date
    var dueDateISO: String
}

struct PlannedReminder: Identifiable, Equatable, Sendable {
    var id: String
    var fireDate: Date
    var title: String
    var body: String
    var chequeID: UUID?
    var kind: ReminderKind
}

struct ReminderPlan: Sendable {
    var items: [PlannedReminder]
    /// The earliest event this plan cannot cover, including the daily-summary horizon.
    var firstUncoveredDate: Date?
}

struct ReminderAcceptanceReport: Sendable {
    var acceptedCount: Int
    var firstUncoveredDate: Date?
}

/// A bounded, deterministic queue. Opening/editing the app replenishes it; background runtime is not assumed.
enum ReminderPlanner {
    static let identifierPrefix = "shekati."
    static let notificationBudget = 60
    static let summaryHorizonDays = 30

    private static func translated(_ key: String, _ code: String) -> String {
        Localization.text(key, language: AppLanguage(rawValue: code) ?? .english)
    }

    static func makePlan(inputs: [ChequeReminderInput], settings: ReminderSettings,
                         now: Date = Date(), calendar suppliedCalendar: Calendar = .current,
                         snoozed: [SnoozedCheque] = []) -> ReminderPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.bankingCalendar.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? suppliedCalendar.timeZone
        let active = inputs.filter { $0.enabled && $0.snapshot.isOutstanding }
        guard !active.isEmpty else { return ReminderPlan(items: [], firstUncoveredDate: nil) }
        let arabic = settings.languageCode.hasPrefix("ar")
        let today = LocalDay(date: now, calendar: calendar)
        var candidates: [PlannedReminder] = []

        for input in active {
            let cheque = input.snapshot
            var chequeSettings = settings
            chequeSettings.hour = input.hour ?? settings.hour
            chequeSettings.minute = input.minute ?? settings.minute
            var sharedBody: String?
            for offset in Set(input.offsets ?? settings.offsets).filter({ (0...365).contains($0) }).sorted() {
                let scheduled = cheque.dueDate.adding(days: -offset, calendar: calendar)
                let day: LocalDay
                if let banking = settings.bankingCalendar {
                    guard let adjusted = banking.reminderDay(for: scheduled, calendar: calendar) else { continue }
                    day = adjusted
                } else { day = scheduled }
                let effectiveOffset = day == cheque.dueDate ? 0 : max(1, offset)
                guard let fireDate = fireDate(on: day, settings: chequeSettings, calendar: calendar), fireDate > now else { continue }
                if sharedBody == nil { sharedBody = chequeContent(cheque: cheque, settings: settings, offset: offset).body }
                candidates.append(PlannedReminder(id: "\(identifierPrefix)cheque.\(cheque.id.uuidString).\(offset)",
                                                  fireDate: fireDate, title: chequeTitle(offset: effectiveOffset, languageCode: settings.languageCode), body: sharedBody!,
                                                  chequeID: cheque.id, kind: .cheque))
            }
            if let snooze = snoozed.filter({ $0.chequeID == cheque.id && $0.dueDateISO == cheque.dueDate.iso && $0.fireDate > now })
                .max(by: { $0.fireDate < $1.fireDate }) {
                if sharedBody == nil { sharedBody = chequeContent(cheque: cheque, settings: settings, offset: nil).body }
                candidates.append(PlannedReminder(id: "\(identifierPrefix)snooze.\(cheque.id.uuidString)",
                                                  fireDate: snooze.fireDate, title: chequeTitle(offset: nil, languageCode: settings.languageCode), body: sharedBody!,
                                                  chequeID: cheque.id, kind: .snooze))
            }
        }

        var summaryUncovered: Date?
        if settings.dailySummary {
            // Date-specific summaries are scheduled only for the next 30 days, so their content is truthful.
            for distance in 0..<summaryHorizonDays {
                let day = today.adding(days: distance, calendar: calendar)
                guard let date = fireDate(on: day, settings: settings, calendar: calendar), date > now else { continue }
                if let summary = makeSummary(day: day, date: date, inputs: active, settings: settings, calendar: calendar) {
                    candidates.append(summary)
                }
            }
            let afterHorizon = today.adding(days: summaryHorizonDays, calendar: calendar)
            // Summaries become relevant three days before a cheque is due and remain relevant if still outstanding.
            let nextRelevantDay = active.map { input in
                max(afterHorizon, input.snapshot.dueDate.adding(days: -3, calendar: calendar))
            }.min()
            if let day = nextRelevantDay { summaryUncovered = fireDate(on: day, settings: settings, calendar: calendar) }
        }

        candidates.sort { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        // A coverage notice itself consumes one slot; never quietly exceed the budget.
        let needsNotice = candidates.count > notificationBudget || summaryUncovered != nil
        let limit = notificationBudget - (needsNotice ? 1 : 0)
        var chosen = Array(candidates.prefix(limit))
        let clippedDate = candidates.dropFirst(limit).first?.fireDate
        let firstUncovered = earliest(clippedDate, summaryUncovered)
        if let date = firstUncovered {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
            // For a nearby cutoff, warn immediately rather than waiting past the first omitted event.
            let immediateDate = now.addingTimeInterval(min(0.01, date.timeIntervalSince(now) / 2))
            let noticeDate = max(immediateDate, min(previousDay, date.addingTimeInterval(-1)))
            chosen.append(PlannedReminder(id: "\(identifierPrefix)coverage", fireDate: noticeDate,
                                          title: arabic ? "حدّث تذكيرات شيكاتك" : translated("Refresh your cheque reminders", settings.languageCode),
                                          body: arabic ? "افتح شيكاتي لتجهيز التذكيرات التالية. التذكيرات المجدولة لها فترة تغطية محدودة."
                                            : translated("Open Shekati to prepare the next reminders. Scheduled reminders have a limited coverage period.", settings.languageCode),
                                          chequeID: nil, kind: .replenishment))
        }
        chosen.sort { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        return ReminderPlan(items: chosen, firstUncoveredDate: firstUncovered)
    }

    static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(a), .some(b)): return min(a, b)
        case let (.some(a), .none): return a
        case let (.none, .some(b)): return b
        case (.none, .none): return nil
        }
    }

    static func chequeContent(cheque: ChequeSnapshot, settings: ReminderSettings, offset: Int?) -> (title: String, body: String) {
        let arabic = settings.languageCode.hasPrefix("ar")
        let title = chequeTitle(offset: offset, languageCode: settings.languageCode)
        if settings.hideDetails {
            return (title, arabic ? "افتح شيكاتي لمراجعة تفاصيل التذكير." : translated("Open Shekati to review your reminder.", settings.languageCode))
        }
        let number = cheque.number.isEmpty ? "" : " #\(NumericInput.latinDigits(cheque.number))"
        let amount = CurrencyMath.format(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode,
                                         locale: Locale(identifier: settings.languageCode))
        let direction = arabic ? (cheque.direction == .incoming ? "وارد" : "صادر")
            : (cheque.direction == .incoming ? "Incoming" : "Outgoing")
        let suffix = cheque.party.isEmpty ? "" : " · \(NumericInput.latinDigits(cheque.party))"
        let body = arabic ? "شيك \(direction)\(number) · \(amount)\(suffix) · الاستحقاق \(cheque.dueDate.iso)"
            : "\(direction) cheque\(number) · \(amount)\(suffix) · Due \(cheque.dueDate.iso)"
        if !arabic && !settings.languageCode.hasPrefix("en") {
            let kind = translated(cheque.direction == .incoming ? "Incoming cheque" : "Outgoing cheque", settings.languageCode)
            let dateLabel = translated("Due date", settings.languageCode)
            return (title, "\(kind)\(number) · \(amount)\(suffix) · \(dateLabel) \(cheque.dueDate.iso)")
        }
        return (title, body)
    }

    private static func chequeTitle(offset: Int?, languageCode: String) -> String {
        let arabic = languageCode.hasPrefix("ar")
        if offset == nil { return arabic ? "تذكير بشيك" : translated("Cheque reminder", languageCode) }
        if arabic { return offset == 0 ? "شيك يستحق اليوم" : "اقترب استحقاق شيك" }
        return offset == 0 ? translated("Cheque due today", languageCode) : translated("Cheque due soon", languageCode)
    }

    /// An add call succeeding is insufficient: the system's accepted queue must cover the intended dates.
    static func confirm(plan: ReminderPlan, acceptedDates: [String: Date]) -> ReminderAcceptanceReport {
        var count = 0
        var uncovered = plan.firstUncoveredDate
        for item in plan.items {
            if let acceptedDate = acceptedDates[item.id], abs(acceptedDate.timeIntervalSince(item.fireDate)) < 1 {
                count += 1
            } else { uncovered = earliest(uncovered, item.fireDate) }
        }
        return ReminderAcceptanceReport(acceptedCount: count, firstUncoveredDate: uncovered)
    }

    private static func fireDate(on day: LocalDay, settings: ReminderSettings, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: min(23, max(0, settings.hour)),
                      minute: min(59, max(0, settings.minute)), second: 0,
                      of: day.date(calendar: calendar), matchingPolicy: .nextTime,
                      repeatedTimePolicy: .first, direction: .forward)
    }

    static func makeSummary(day: LocalDay, date: Date, inputs: [ChequeReminderInput],
                                    settings: ReminderSettings, calendar: Calendar) -> PlannedReminder? {
        let due = inputs.filter { $0.snapshot.dueDate == day }.count
        let overdue = inputs.filter { $0.snapshot.dueDate < day }.count
        let through = day.adding(days: 3, calendar: calendar)
        let upcoming = inputs.filter { $0.snapshot.dueDate > day && $0.snapshot.dueDate <= through }.count
        guard due + overdue + upcoming > 0 else { return nil }
        let arabic = settings.languageCode.hasPrefix("ar")
        let body: String
        if settings.hideDetails {
            body = arabic ? "افتح شيكاتي للاطلاع على ملخص اليوم." : translated("Open Shekati to view today's summary.", settings.languageCode)
        } else if !arabic && !settings.languageCode.hasPrefix("en") {
            body = [(translated("Due today", settings.languageCode), due), (translated("Overdue", settings.languageCode), overdue), (translated("Next 3 days", settings.languageCode), upcoming)]
                .map { "\($0.0): \($0.1)" }.joined(separator: " · ")
        } else {
            body = arabic ? "يستحق اليوم: \(due) · متأخرة: \(overdue) · خلال 3 أيام: \(upcoming)"
                : "Due today: \(due) · Overdue: \(overdue) · Next 3 days: \(upcoming)"
        }
        return PlannedReminder(id: "\(identifierPrefix)summary.\(day.iso)", fireDate: date,
                               title: arabic ? "ملخص شيكاتك" : translated("Your cheque summary", settings.languageCode),
                               body: body, chequeID: nil, kind: .dailySummary)
    }
}
