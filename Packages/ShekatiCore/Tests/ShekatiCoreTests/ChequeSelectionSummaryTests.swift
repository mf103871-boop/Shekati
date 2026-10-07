import Foundation
import XCTest
@testable import ShekatiCore

final class ChequeSelectionSummaryTests: XCTestCase {
    private func cheque(amount: Int64, currency: String = "JOD", id: UUID = UUID()) -> ChequeSnapshot {
        ChequeSnapshot(id: id, direction: .outgoing, amountMinorUnits: amount,
                       currencyCode: currency, dueDate: LocalDay(iso: "2026-10-07")!)
    }

    func testZeroTwoAndThreeDecimalCurrenciesKeepExactMinorUnits() {
        for (currency, first, second, expected) in [
            ("JPY", Int64(123), Int64(456), Int64(579)),
            ("USD", Int64(12345), Int64(678), Int64(13023)),
            ("JOD", Int64(123456), Int64(789), Int64(124245))
        ] {
            let records = [cheque(amount: first, currency: currency), cheque(amount: second, currency: currency)]
            let result = ChequeSelectionSummary(cheques: records, selectedIDs: Set(records.map(\.id)))
            XCTAssertEqual(result.totalMinorUnits, expected, currency)
            XCTAssertEqual(result.currencyCode, currency)
            XCTAssertEqual(result.count, 2)
            XCTAssertFalse(result.hasCurrencyConflict)
            XCTAssertFalse(result.hasOverflow)
            XCTAssertFalse(result.hasInvalidValues)
        }
    }

    func testDuplicateSnapshotsCountOnlyOnceAndHiddenIDsAreExcluded() {
        let visible = cheque(amount: 1250)
        let hidden = cheque(amount: 99000)
        let unselected = cheque(amount: 100)
        let result = ChequeSelectionSummary(cheques: [visible, visible, unselected],
                                           selectedIDs: [visible.id, hidden.id, UUID()])
        XCTAssertEqual(result.selectedIDs, [visible.id])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.totalMinorUnits, 1250)
    }

    func testEmptyOrStaleSelectionHasZeroTotalAndNoCurrency() {
        let record = cheque(amount: 100)
        let selections: [Set<UUID>] = [[], [UUID()]]
        for selected in selections {
            let result = ChequeSelectionSummary(cheques: [record], selectedIDs: selected)
            XCTAssertEqual(result.count, 0)
            XCTAssertTrue(result.selectedIDs.isEmpty)
            XCTAssertEqual(result.totalMinorUnits, 0)
            XCTAssertNil(result.currencyCode)
            XCTAssertFalse(result.hasCurrencyConflict)
            XCTAssertFalse(result.hasOverflow)
            XCTAssertFalse(result.hasInvalidValues)
        }
    }

    func testCurrencyCodeIsTrimmedAndNormalizedBeforeComparison() {
        let records = [cheque(amount: 100, currency: " jod \n"), cheque(amount: 200, currency: "JOD")]
        let result = ChequeSelectionSummary(cheques: records, selectedIDs: Set(records.map(\.id)))
        XCTAssertEqual(result.currencyCode, "JOD")
        XCTAssertEqual(result.totalMinorUnits, 300)
        XCTAssertFalse(result.hasCurrencyConflict)
    }

    func testDifferentCurrenciesNeverProduceACombinedTotal() {
        let records = [cheque(amount: 100, currency: "USD"), cheque(amount: 200, currency: "JOD")]
        let result = ChequeSelectionSummary(cheques: records, selectedIDs: Set(records.map(\.id)))
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.hasCurrencyConflict)
        XCTAssertNil(result.currencyCode)
        XCTAssertNil(result.totalMinorUnits)
    }

    func testExactMaximumIsAllowedButOverflowNeverWrapsOrResets() {
        let maximum = cheque(amount: Int64.max)
        let exact = ChequeSelectionSummary(cheques: [maximum, maximum], selectedIDs: [maximum.id])
        XCTAssertEqual(exact.totalMinorUnits, Int64.max)
        XCTAssertFalse(exact.hasOverflow)

        let records = [maximum, cheque(amount: 1), cheque(amount: 50)]
        for ordering in [records, Array(records.reversed())] {
            let result = ChequeSelectionSummary(cheques: ordering, selectedIDs: Set(records.map(\.id)))
            XCTAssertEqual(result.count, 3)
            XCTAssertTrue(result.hasOverflow)
            XCTAssertNil(result.totalMinorUnits)
        }
    }

    func testInvalidAmountsAndMissingCurrencySuppressTheTotal() {
        for invalid in [cheque(amount: -25), cheque(amount: 0), cheque(amount: 100, currency: " \n")] {
            let valid = cheque(amount: 500)
            let result = ChequeSelectionSummary(cheques: [valid, invalid], selectedIDs: [valid.id, invalid.id])
            XCTAssertEqual(result.count, 2)
            XCTAssertTrue(result.hasInvalidValues)
            XCTAssertNil(result.totalMinorUnits)
        }
    }
}
