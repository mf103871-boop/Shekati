import XCTest
import PDFKit
import ShekatiCore
@testable import Shekati

@MainActor
final class DisputedReportTests: XCTestCase {
    func testConflictingPaymentsWithholdTheCurrencyAndRemainingExportUntilReconciled() throws {
        let day = try XCTUnwrap(LocalDay(iso: "2026-11-20"))
        func cheque(_ code: String, _ number: String) -> ChequeRecord {
            ChequeRecord(snapshot: .init(direction: .outgoing, amountMinorUnits: 10_000, currencyCode: code, dueDate: day, number: number))
        }
        let disputed = cheque("USD", "0001")
        let sameCurrency = cheque("USD", "0002")
        let otherCurrency = cheque("EUR", "0003")
        let records = [disputed, sameCurrency, otherCurrency]
        let accountID = UUID()
        let entries = [7_000, 8_000].map { amount in
            LedgerEventRecord(.init(chequeID: disputed.id, accountID: accountID, kind: .partialBank, day: day,
                                    amount: Int64(amount), currency: "USD"))
        }

        let rows = ChequeReportRows(ids: records.map(\.id), records: records, events: entries)
        XCTAssertEqual(rows.disputedCurrencies, ["USD"])
        XCTAssertFalse(rows.canExportRemaining)
        XCTAssertEqual(rows.outstanding.map(\.id), [otherCurrency.id])
        XCTAssertEqual(rows.originals.map(\.amountMinorUnits), [10_000, 10_000, 10_000])
        let clean = ChequeReportRows(ids: [otherCurrency.id], records: records, events: entries)
        XCTAssertTrue(clean.canExportRemaining)
        let pdf = ChequePDFReport.generate(cheques: clean.outstanding, language: .english, basis: .remaining)
        XCTAssertTrue(try XCTUnwrap(PDFDocument(data: pdf)?.string).contains("Remaining amount"))
    }
}
