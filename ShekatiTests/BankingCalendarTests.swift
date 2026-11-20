import XCTest
import ShekatiCore
@testable import Shekati

final class BankingCalendarTests: XCTestCase {
    func testAChangeOfBankHolidayOrZoneForcesNotificationRefresh() {
        var settings = ReminderSettings(offsets: [0], hour: 9, minute: 0, dailySummary: false, hideDetails: true,
                                        languageCode: "en", bankingCalendar: BankingCalendar())
        func key() -> [[String]] {
            ReminderRequestPolicy.refreshKey(inputs: [], settings: settings, dayRevision: 0, authorizationStatus: 2)
        }
        let original = key()
        settings.bankingCalendar?.holidays = ["2026-11-20"]
        let changed = key()
        XCTAssertNotEqual(original, changed)
        settings.bankingCalendar?.timeZoneID = "Pacific/Kiritimati"
        XCTAssertNotEqual(changed, key())
    }

    func testFridayDueDateAfterTwoBankHolidaysMovesOnlyTheReminder() throws {
        let due = try XCTUnwrap(LocalDay(iso: "2026-11-20"))
        let calendar = BankingCalendar(shiftsReminders: true, region: "JO", timeZoneID: "Asia/Amman", closedWeekdays: [6, 7], holidays: ["2026-11-19", "2026-11-18"])
        XCTAssertEqual(calendar.reminderDay(for: due, calendar: Calendar(identifier: .gregorian))?.iso, "2026-11-17")
        XCTAssertEqual(due.iso, "2026-11-20")
    }
}

