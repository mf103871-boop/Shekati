import Foundation
import XCTest
@testable import ShekatiCore

final class LocalDayTests: XCTestCase {
    func testStrictGregorianValidation() {
        XCTAssertEqual(LocalDay(iso: "2024-02-29")?.iso, "2024-02-29")
        for invalid in ["2025-02-29", "2024-04-31", "2024-00-01", "2024-13-01", "0000-01-01", "2024-1-01", "2024-01-01T00:00:00Z", "٢٠٢٤-٠١-٠١", "garbage"] {
            XCTAssertNil(LocalDay(iso: invalid), invalid)
        }
    }

    func testCalendarAdditionCrossesDaylightSavingWithoutChangingCivilIdentity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = LocalDay(iso: "2026-03-08")!
        let fall = LocalDay(iso: "2026-11-01")!
        XCTAssertEqual(spring.adding(days: 1, calendar: calendar).iso, "2026-03-09")
        XCTAssertEqual(fall.adding(days: 1, calendar: calendar).iso, "2026-11-02")
        XCTAssertEqual(spring.adding(days: -1, calendar: calendar).iso, "2026-03-07")
        XCTAssertEqual(spring.adding(days: 1, calendar: calendar).date(calendar: calendar).timeIntervalSince(spring.date(calendar: calendar)), 23 * 3600)
        XCTAssertEqual(fall.adding(days: 1, calendar: calendar).date(calendar: calendar).timeIntervalSince(fall.date(calendar: calendar)), 25 * 3600)
    }

    func testDateIdentityInMultipleTimeZonesAndNonGregorianUserCalendar() {
        let expected = LocalDay(iso: "2026-10-03")!
        for zone in ["Asia/Amman", "Pacific/Honolulu", "Pacific/Auckland", "Europe/London"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(LocalDay(date: expected.date(calendar: calendar), calendar: calendar), expected)
            var islamicCalendar = Calendar(identifier: .islamicCivil)
            islamicCalendar.timeZone = calendar.timeZone
            XCTAssertEqual(LocalDay(date: expected.date(calendar: calendar), calendar: islamicCalendar), expected)
        }
    }

    func testLeapYearMonthAndYearBoundaries() {
        XCTAssertEqual(LocalDay(iso: "2024-02-28")!.adding(days: 2).iso, "2024-03-01")
        XCTAssertEqual(LocalDay(iso: "2025-12-31")!.adding(days: 1).iso, "2026-01-01")
        XCTAssertTrue(LocalDay(iso: "2025-12-31")! < LocalDay(iso: "2026-01-01")!)
    }

    func testCivilArithmeticDoesNotSkipDateAfterDatelineChange() {
        var apia = Calendar(identifier: .gregorian)
        apia.timeZone = TimeZone(identifier: "Pacific/Apia")!
        XCTAssertEqual(LocalDay(iso: "2011-12-29")!.adding(days: 1, calendar: apia).iso, "2011-12-30")
    }

    func testCodingUsesDateOnlyStringAndRejectsInvalidPayload() throws {
        let date = LocalDay(iso: "2026-10-03")!
        XCTAssertEqual(String(data: try JSONEncoder().encode(date), encoding: .utf8), "\"2026-10-03\"")
        XCTAssertEqual(try JSONDecoder().decode(LocalDay.self, from: Data("\"2026-10-03\"".utf8)), date)
        XCTAssertThrowsError(try JSONDecoder().decode(LocalDay.self, from: Data("\"2026-02-30\"".utf8)))
    }
}
