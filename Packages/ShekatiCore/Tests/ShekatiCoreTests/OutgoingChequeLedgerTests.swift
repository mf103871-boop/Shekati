import XCTest
@testable import ShekatiCore

final class OutgoingChequeLedgerTests: XCTestCase {
    func testListsOnlyOutgoingChequesInChequeDateOrderWithStableTies() {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = early.addingTimeInterval(60)
        let cheques = [
            cheque("2026-10-20", 1_153_000, number: "649", createdAt: early),
            cheque("2026-09-25", 731_250, number: "550", createdAt: early),
            cheque("2026-09-29", 254_000, number: "634", createdAt: late),
            cheque("2026-09-29", 353_100, number: "633", createdAt: early),
            cheque("2026-09-26", 900_000, number: "INCOMING", direction: .incoming)
        ]
        let ledger = OutgoingChequeLedger(cheques: cheques)
        XCTAssertEqual(ledger.rows.map(\.cheque.number), ["550", "633", "634", "649"])
    }

    func testBalanceIsWhatRemainsOwedFromEachRowAndSkipsPaidAndCancelledCheques() {
        let ledger = OutgoingChequeLedger(cheques: [
            cheque("2026-10-01", 1_000_000, number: "1"),
            cheque("2026-10-02", 200_000, number: "2", status: .settled, actual: "2026-10-02"),
            cheque("2026-10-03", 300_000, number: "3", status: .returned),
            cheque("2026-10-04", 400_000, number: "4", status: .cancelled),
            cheque("2026-10-05", 50_500, number: "5")
        ])
        XCTAssertEqual(ledger.rows.map(\.remainingMinorUnits), [1_350_500, 350_500, 350_500, 50_500, 50_500])
        XCTAssertFalse(ledger.hasCurrencyConflict)
    }

    func testBarsAreRelativeToTheLargestAmount() {
        let ledger = OutgoingChequeLedger(cheques: [
            cheque("2026-10-01", 6_000_000, number: "666"),
            cheque("2026-10-02", 1_500_000, number: "669"),
            cheque("2026-10-03", 0, number: "zero")
        ])
        XCTAssertEqual(ledger.rows.map(\.barFraction), [1, 0.25, 0])
        XCTAssertEqual(OutgoingChequeLedger(cheques: []).rows, [])
    }

    func testOverflowingBalanceIsReportedAsUnavailableInsteadOfWrapping() {
        let ledger = OutgoingChequeLedger(cheques: [
            cheque("2026-10-01", 5, number: "a"),
            cheque("2026-10-02", Int64.max, number: "b"),
            cheque("2026-10-03", 1, number: "c")
        ])
        XCTAssertNil(ledger.rows[0].remainingMinorUnits)
        XCTAssertNil(ledger.rows[1].remainingMinorUnits)
        XCTAssertEqual(ledger.rows[2].remainingMinorUnits, 1)
    }

    func testMixedCurrenciesAreFlagged() {
        var other = cheque("2026-10-02", 1_000, number: "2")
        other.currencyCode = "usd"
        XCTAssertTrue(OutgoingChequeLedger(cheques: [cheque("2026-10-01", 1_000, number: "1"), other]).hasCurrencyConflict)
    }

    func testSheetDateAndPlainAmountText() {
        XCTAssertEqual(OutgoingChequeLedger.dateText(LocalDay(iso: "2026-10-04")!), "04/10/2026")
        XCTAssertEqual(OutgoingChequeLedger.dateText(LocalDay(iso: "2027-01-20")!), "20/01/2027")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 731_250, currencyCode: "JOD"), "731.25")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 950_000, currencyCode: "JOD"), "950")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 1_449_571, currencyCode: "JOD"), "1449.571")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 100_062_000, currencyCode: "JOD"), "100062")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 10_000, currencyCode: "JOD"), "10")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 0, currencyCode: "JOD"), "0")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 12_550, currencyCode: "USD"), "125.5")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: 1_500, currencyCode: "JPY"), "1500")
        XCTAssertEqual(CurrencyMath.plain(minorUnits: -500, currencyCode: "JOD"), "-0.5")
    }

    private func cheque(_ due: String, _ amount: Int64, number: String, direction: ChequeDirection = .outgoing,
                        status: ChequeStatus = .pending, actual: String? = nil,
                        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ChequeSnapshot {
        ChequeSnapshot(direction: direction, status: status, amountMinorUnits: amount, currencyCode: "JOD",
                       dueDate: LocalDay(iso: due)!, actualDate: actual.flatMap(LocalDay.init(iso:)),
                       number: number, party: "Demo", createdAt: createdAt)
    }
}
