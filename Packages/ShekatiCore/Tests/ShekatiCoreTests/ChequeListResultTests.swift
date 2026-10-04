import Foundation
import XCTest
@testable import ShekatiCore

final class ChequeListResultTests: XCTestCase {
    private let today = LocalDay(iso: "2026-10-04")!

    func testDirectionTotalsRemainSeparateWithHistoryAndThreeDecimalCurrency() {
        let values = [cheque(amount: 1_001), cheque(amount: 2_002, status: .settled),
                      cheque(amount: 4_003, direction: .outgoing),
                      cheque(amount: 5_004, direction: .outgoing, status: .cancelled)]
        let all = ChequeListResult(cheques: values, filter: .init(), sort: .amount, ascending: true, today: today)
        XCTAssertEqual(all.totals.incomingMinorUnits, 3_003)
        XCTAssertEqual(all.totals.outgoingMinorUnits, 9_007)
        XCTAssertEqual(all.totals.incomingCount, 2)
        XCTAssertEqual(all.totals.outgoingCount, 2)
        let outstanding = ChequeListResult(cheques: values, filter: .init(outstandingOnly: true),
                                           sort: .dueDate, ascending: true, today: today)
        XCTAssertEqual(outstanding.totals.incomingMinorUnits, 1_001)
        XCTAssertEqual(outstanding.totals.outgoingMinorUnits, 4_003)
        XCTAssertEqual(outstanding.cheques.count, 2)
    }

    func testOverflowAffectsOnlyItsDirectionAndMixedCurrenciesAreIdentified() {
        var differentCurrency = cheque(amount: 25, direction: .outgoing)
        differentCurrency.currencyCode = "USD"
        let totals = ChequeDirectionTotals(cheques: [cheque(amount: .max), cheque(amount: 1), differentCurrency])
        XCTAssertNil(totals.incomingMinorUnits)
        XCTAssertEqual(totals.outgoingMinorUnits, 25)
        XCTAssertTrue(totals.hasAmountOverflow)
        XCTAssertTrue(totals.hasCurrencyConflict)
    }

    func testCombinedSearchDateDirectionAndStatusTotalsAgreeWithReturnedRows() {
        let fixture = (0..<1_000).map { index in
            cheque(amount: Int64(index + 1), direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                   status: index.isMultiple(of: 3) ? .returned : .pending,
                   offset: index % 21 - 10, number: String(format: "%06d", index), bank: "Bank A")
        }
        let filter = ChequeFilter(query: "BANK A", direction: .incoming, status: .returned,
                                 from: today, through: today.adding(days: 7), outstandingOnly: true)
        let result = ChequeListResult(cheques: fixture, filter: filter, sort: .dueDate, ascending: true, today: today)
        let expected = fixture.filter { $0.direction == .incoming && $0.status == .returned &&
            $0.dueDate >= today && $0.dueDate <= today.adding(days: 7) }
        XCTAssertEqual(Set(result.cheques.map(\.id)), Set(expected.map(\.id)))
        XCTAssertEqual(result.totals.incomingMinorUnits, expected.reduce(Int64(0)) { $0 + $1.amountMinorUnits })
        XCTAssertEqual(result.totals.outgoingMinorUnits, 0)
    }

    func testThousandRowSearchAndTotalsPerformance() { measureList(count: 1_000) }
    func testTenThousandRowSearchAndTotalsPerformance() { measureList(count: 10_000) }

    private func measureList(count: Int) {
        let fixture = (0..<count).map { index in
            cheque(amount: Int64(index + 1), direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                   offset: index % 31, number: String(format: "%06d", index), bank: "Demo Bank")
        }
        let filter = ChequeFilter(query: "demo", from: today, through: today.adding(days: 7), outstandingOnly: true)
        // XCTest records a repeatable algorithm baseline; device UI/CPU/memory profiling is a separate check.
        measure(metrics: [XCTClockMetric()]) {
            let result = ChequeListResult(cheques: fixture, filter: filter, sort: .amount, ascending: false, today: today)
            XCTAssertFalse(result.cheques.isEmpty)
            XCTAssertEqual(result.totals.incomingCount + result.totals.outgoingCount, result.cheques.count)
            XCTAssertFalse(result.totals.hasAmountOverflow)
        }
    }

    private func cheque(amount: Int64, direction: ChequeDirection = .incoming,
                        status: ChequeStatus = .pending, offset: Int = 0,
                        number: String = "000123", bank: String = "Demo Bank") -> ChequeSnapshot {
        ChequeSnapshot(direction: direction, status: status, amountMinorUnits: amount, currencyCode: "JOD",
                       dueDate: today.adding(days: offset), number: number, bank: bank,
                       party: "Demo party", createdAt: Date(timeIntervalSince1970: 1))
    }
}
