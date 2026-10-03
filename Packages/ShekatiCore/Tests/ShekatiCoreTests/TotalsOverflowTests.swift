import XCTest
@testable import ShekatiCore

final class TotalsOverflowTests: XCTestCase {
    func testTotalsExposeOverflowInsteadOfClaimingAClampedTotalIsExact() throws {
        let day = try XCTUnwrap(LocalDay(iso: "2026-10-03"))
        let largest = ChequeSnapshot(direction: .incoming, amountMinorUnits: Int64.max,
                                     currencyCode: "USD", dueDate: day)
        let extra = ChequeSnapshot(direction: .incoming, amountMinorUnits: 1,
                                   currencyCode: "USD", dueDate: day)
        XCTAssertFalse(DashboardMetrics(cheques: [largest], today: day).hasAmountOverflow)
        XCTAssertTrue(DashboardMetrics(cheques: [largest, extra], today: day).hasAmountOverflow)
        var outgoing = extra
        outgoing.direction = .outgoing
        XCTAssertTrue(DashboardMetrics(cheques: [largest, outgoing], today: day).hasAmountOverflow)
        outgoing.status = .settled
        XCTAssertFalse(DashboardMetrics(cheques: [largest, outgoing], today: day).hasAmountOverflow)
    }
}
