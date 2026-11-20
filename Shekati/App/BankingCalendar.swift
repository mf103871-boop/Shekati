import Foundation
import ShekatiCore

struct BankingCalendar: Equatable, Codable, Sendable {
    var shiftsReminders = false
    var region = Locale.current.region?.identifier ?? "US"
    var timeZoneID = TimeZone.current.identifier
    // Foundation weekday numbering starts at Sunday = 1.
    var closedWeekdays: Set<Int> = []
    var holidays: Set<String> = []

    var reminderSignature: [String] {
        [region, timeZoneID, String(shiftsReminders), closedWeekdays.sorted().map(String.init).joined(separator: ","),
         holidays.sorted().joined(separator: ",")]
    }

    static func defaultWeekends(in region: String) -> Set<Int> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_" + region)
        let start = LocalDay(iso: "2026-11-15")!
        return Set((0..<7).compactMap { offset in
            let date = start.adding(days: offset).date(calendar: calendar)
            return calendar.isDateInWeekend(date) ? calendar.component(.weekday, from: date) : nil
        })
    }

    func reminderDay(for scheduled: LocalDay, calendar: Calendar) -> LocalDay? {
        guard shiftsReminders else { return scheduled }
        guard closedWeekdays.intersection(1...7).count < 7 else { return nil }
        var day = scheduled
        for _ in 0..<(7 * (holidays.count + 1) + 1) {
            let weekday = calendar.component(.weekday, from: day.date(calendar: calendar))
            if !closedWeekdays.contains(weekday), !holidays.contains(day.iso) { return day }
            day = day.adding(days: -1)
        }
        return nil
    }
}

