import Foundation
import XCTest
@testable import ShekatiCore

final class ChequeAvailabilityTests: XCTestCase {
    private func day(_ iso: String) -> LocalDay { LocalDay(iso: iso)! }

    private func cheque(_ iso: String, direction: ChequeDirection = .outgoing,
                        status: ChequeStatus = .pending, issueDate: String? = nil) -> ChequeSnapshot {
        ChequeSnapshot(direction: direction, status: status, amountMinorUnits: 1000, currencyCode: "JOD",
                       dueDate: day(iso), issueDate: issueDate.map(day))
    }

    func testOnlyOutstandingOutgoingDueDatesAreOccupied() {
        let records = [
            cheque("2026-10-07"),
            cheque("2026-10-08", status: .returned),
            cheque("2026-10-09", status: .settled),
            cheque("2026-10-10", status: .cancelled),
            cheque("2026-10-11", direction: .incoming),
            cheque("2026-10-12", direction: .incoming, status: .returned)
        ]
        let result = ChequeAvailability(cheques: records, from: day("2026-10-07"), through: day("2026-10-13"))
        XCTAssertTrue(result.isValidRange)
        XCTAssertEqual(result.freeDays.map(\.iso), ["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13"])
    }

    func testInclusiveEndpointsAndOneDayRange() {
        let records = [cheque("2026-10-07"), cheque("2026-10-09"), cheque("2026-10-06"), cheque("2026-10-10")]
        let result = ChequeAvailability(cheques: records, from: day("2026-10-07"), through: day("2026-10-09"))
        XCTAssertEqual(result.freeDays, [day("2026-10-08")])
        let occupiedToday = ChequeAvailability(cheques: records, from: day("2026-10-07"), through: day("2026-10-07"))
        XCTAssertTrue(occupiedToday.isValidRange)
        XCTAssertTrue(occupiedToday.freeDays.isEmpty)
        let freeToday = ChequeAvailability(cheques: records, from: day("2026-10-08"), through: day("2026-10-08"))
        XCTAssertEqual(freeToday.freeDays, [day("2026-10-08")])
    }

    func testIssueDateAndRepeatedChequesDoNotChangeAvailability() {
        let record = cheque("2026-10-09", issueDate: "2026-10-07")
        let result = ChequeAvailability(cheques: [record, record], from: day("2026-10-07"), through: day("2026-10-09"))
        XCTAssertEqual(result.freeDays.map(\.iso), ["2026-10-07", "2026-10-08"])
    }

    func testLeapDayAndMonthAndYearBoundaries() {
        let leap = ChequeAvailability(cheques: [], from: day("2028-02-28"), through: day("2028-03-01"))
        XCTAssertEqual(leap.freeDays.map(\.iso), ["2028-02-28", "2028-02-29", "2028-03-01"])
        let ordinary = ChequeAvailability(cheques: [], from: day("2027-02-28"), through: day("2027-03-01"))
        XCTAssertEqual(ordinary.freeDays.map(\.iso), ["2027-02-28", "2027-03-01"])
        let year = ChequeAvailability(cheques: [], from: day("2026-12-31"), through: day("2027-01-01"))
        XCTAssertEqual(year.freeDays.map(\.iso), ["2026-12-31", "2027-01-01"])
    }

    func testCivilDatesStayContinuousAcrossDSTAndSkippedLocalDate() {
        // These dates include a DST transition and Samoa's skipped local 2011-12-30.
        // Availability uses civil dates, so both ranges must preserve every calendar day.
        for (start, end, expected) in [
            ("2026-03-07", "2026-03-10", ["2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"]),
            ("2011-12-29", "2011-12-31", ["2011-12-29", "2011-12-30", "2011-12-31"])
        ] {
            let result = ChequeAvailability(cheques: [], from: day(start), through: day(end))
            XCTAssertTrue(result.isValidRange)
            XCTAssertEqual(result.freeDays.map(\.iso), expected)
        }
    }

    func testExactly366DaysIsValidAndLongerRangeIsRejectedWithoutPartialResults() {
        let start = day("2028-01-01")
        let valid = ChequeAvailability(cheques: [], from: start, through: day("2028-12-31"))
        XCTAssertTrue(valid.isValidRange)
        XCTAssertEqual(valid.freeDays.count, ChequeAvailability.maxDayCount)
        XCTAssertEqual(valid.freeDays.first, start)
        XCTAssertEqual(valid.freeDays.last, day("2028-12-31"))

        for end in [day("2029-01-01"), day("9999-12-31")] {
            let invalid = ChequeAvailability(cheques: [], from: start, through: end)
            XCTAssertFalse(invalid.isValidRange)
            XCTAssertTrue(invalid.freeDays.isEmpty)
        }
    }

    func testReversedRangeIsInvalid() {
        let result = ChequeAvailability(cheques: [], from: day("2026-10-08"), through: day("2026-10-07"))
        XCTAssertFalse(result.isValidRange)
        XCTAssertTrue(result.freeDays.isEmpty)
    }
}
