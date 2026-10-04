import Foundation
import XCTest
import ShekatiCore
@testable import Shekati

final class ChequeEntryAssistanceTests: XCTestCase {
    func testSuggestionsTrimDeduplicateExcludeCurrentValueAndKeepRecentOrder() {
        let values = ["  Acme Bank ", "ACME BANK", "Other Bank", "", "Third Bank"]
        XCTAssertEqual(ChequeEntryAssistance.suggestions(from: values, matching: "bank", limit: 2),
                       ["Acme Bank", "Other Bank"])
        XCTAssertEqual(ChequeEntryAssistance.suggestions(from: values, matching: "Acme Bank"), [])
        XCTAssertEqual(ChequeEntryAssistance.suggestions(from: values, matching: "", limit: 0), [])
    }

    func testIdentityWarningKeepsLeadingZerosAndNormalizesArabicDigits() {
        let original = fixture(number: "000123")
        XCTAssertEqual(ChequeEntryAssistance.probableDuplicateIDs(for: fixture(number: "٠٠٠١٢٣"), among: [original]), [original.id])
        XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: fixture(number: "123"), among: [original]).isEmpty)
    }

    func testSameBankAndNumberWarnEvenWhenAmountOrDateWasMistyped() {
        let original = fixture()
        var editedDraft = fixture()
        editedDraft.amountMinorUnits = 123_456
        editedDraft.dueDate = LocalDay(iso: "2026-12-15")!
        XCTAssertEqual(ChequeEntryAssistance.probableDuplicateIDs(for: editedDraft, among: [original]), [original.id])
    }

    func testDifferentBanksAccountsDirectionsAndCurrenciesDoNotCreateFalseWarnings() {
        let original = fixture()
        var differentBank = fixture(); differentBank.bank = "Another Bank"
        var differentAccount = fixture(); differentAccount.accountReference = "OTHER-ACCOUNT"
        var differentDirection = fixture(); differentDirection.direction = .outgoing
        var differentCurrency = fixture(); differentCurrency.currencyCode = "JOD"
        for draft in [differentBank, differentAccount, differentDirection, differentCurrency] {
            XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]).isEmpty)
        }
    }

    func testEditingTheExistingRecordDoesNotWarnAboutItself() {
        let original = fixture()
        XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: original, among: [original], excluding: original.id).isEmpty)
    }

    func testMissingBankUsesNumberAmountAndDateButNotNumberAlone() {
        var original = fixture(); original.bank = ""; original.accountReference = ""
        var draft = original; draft.id = UUID()
        XCTAssertEqual(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]), [original.id])
        draft.dueDate = LocalDay(iso: "2026-12-15")!
        XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]).isEmpty)
    }

    func testChequeWithoutNumberRequiresNonemptyNameMatchingAmountAndDate() {
        let original = fixture(number: "")
        var draft = fixture(number: ""); draft.party = "demo person"
        XCTAssertEqual(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]), [original.id])
        draft.party = ""
        XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]).isEmpty)
        draft.party = "Demo Person"; draft.amountMinorUnits += 1
        XCTAssertTrue(ChequeEntryAssistance.probableDuplicateIDs(for: draft, among: [original]).isEmpty)
    }

    private func fixture(number: String = "000123") -> ChequeSnapshot {
        ChequeSnapshot(direction: .incoming, amountMinorUnits: 12_550, currencyCode: "USD",
                       dueDate: LocalDay(iso: "2026-11-01")!, number: number,
                       bank: "Demo Bank", party: "Demo Person", accountReference: "MAIN-ACCOUNT")
    }
}
