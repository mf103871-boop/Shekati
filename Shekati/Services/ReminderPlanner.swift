import Foundation
import ShekatiCore

struct ReminderSettings: Equatable, Sendable {
    var offsets: [Int]
    var hour: Int
    var minute: Int
    var dailySummary: Bool
    var hideDetails: Bool
    var languageCode: String
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

enum ReminderKind: String, Sendable { case cheque, dailySummary, replenishment }

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

    static func makePlan(inputs: [ChequeReminderInput], settings: ReminderSettings,
                         now: Date = Date(), calendar suppliedCalendar: Calendar = .current) -> ReminderPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = suppliedCalendar.timeZone
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
            for offset in Set(input.offsets ?? settings.offsets).filter({ (0...365).contains($0) }).sorted() {
                let day = cheque.dueDate.adding(days: -offset, calendar: calendar)
                guard let fireDate = fireDate(on: day, settings: chequeSettings, calendar: calendar), fireDate > now else { continue }
                let number = cheque.number.isEmpty ? "" : " #\(cheque.number)"
                let title: String
                if arabic { title = offset == 0 ? "شيك يستحق اليوم" : "اقترب استحقاق شيك" }
                else { title = offset == 0 ? "Cheque due today" : "Cheque due soon" }
                let body: String
                if settings.hideDetails {
                    body = arabic ? "افتح شيكاتي لمراجعة تفاصيل التذكير." : "Open Shekati to review your reminder."
                } else {
                    let amount = CurrencyMath.format(minorUnits: cheque.amountMinorUnits,
                                                     currencyCode: cheque.currencyCode,
                                                     locale: Locale(identifier: arabic ? "ar" : "en"))
                    let direction = arabic ? (cheque.direction == .incoming ? "وارد" : "صادر")
                        : (cheque.direction == .incoming ? "Incoming" : "Outgoing")
                    let suffix = cheque.party.isEmpty ? "" : " · \(cheque.party)"
                    let due = cheque.dueDate.iso
                    body = arabic ? "شيك \(direction)\(number) · \(amount)\(suffix) · الاستحقاق \(due)"
                        : "\(direction) cheque\(number) · \(amount)\(suffix) · Due \(due)"
                }
                candidates.append(PlannedReminder(id: "\(identifierPrefix)cheque.\(cheque.id.uuidString).\(offset)",
                                                  fireDate: fireDate, title: title, body: body,
                                                  chequeID: cheque.id, kind: .cheque))
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
                                          title: arabic ? "حدّث تذكيرات شيكاتك" : "Refresh your cheque reminders",
                                          body: arabic ? "افتح شيكاتي لتجهيز التذكيرات التالية. التذكيرات المجدولة لها فترة تغطية محدودة."
                                            : "Open Shekati to prepare the next reminders. Scheduled reminders have a limited coverage period.",
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

    private static func makeSummary(day: LocalDay, date: Date, inputs: [ChequeReminderInput],
                                    settings: ReminderSettings, calendar: Calendar) -> PlannedReminder? {
        let due = inputs.filter { $0.snapshot.dueDate == day }.count
        let overdue = inputs.filter { $0.snapshot.dueDate < day }.count
        let through = day.adding(days: 3, calendar: calendar)
        let upcoming = inputs.filter { $0.snapshot.dueDate > day && $0.snapshot.dueDate <= through }.count
        guard due + overdue + upcoming > 0 else { return nil }
        let arabic = settings.languageCode.hasPrefix("ar")
        let body: String
        if settings.hideDetails {
            body = arabic ? "افتح شيكاتي للاطلاع على ملخص اليوم." : "Open Shekati to view today's summary."
        } else {
            body = arabic ? "يستحق اليوم: \(due) · متأخرة: \(overdue) · خلال 3 أيام: \(upcoming)"
                : "Due today: \(due) · Overdue: \(overdue) · Next 3 days: \(upcoming)"
        }
        return PlannedReminder(id: "\(identifierPrefix)summary.\(day.iso)", fireDate: date,
                               title: arabic ? "ملخص شيكاتك" : "Your cheque summary",
                               body: body, chequeID: nil, kind: .dailySummary)
    }
}
