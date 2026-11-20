import XCTest
@testable import ShekatiCore

final class BankLedgerTests: XCTestCase {
    private let account = UUID()
    private let cheque = UUID()
    private let day = LocalDay(iso: "2026-11-20")!

    private func op(_ kind: LedgerAction, amount: Int64 = 0, parent: UUID? = nil,
                    related: UUID? = nil, party: String = "") -> LedgerOperation {
        LedgerOperation(parentID: parent, chequeID: cheque, accountID: account, kind: kind,
                        day: day, amount: amount, party: party, relatedID: related, currency: "JOD")
    }

    private func position(_ ops: [LedgerOperation], initial: PaperState = .inHand) -> ChequePosition {
        ChequePosition(original: 1_250_000, direction: .incoming, baseline: initial, currency: "JOD", operations: ops)
    }

    func testWeeklyReserveAndDatedDeficitAreIndependent() throws {
        func item(_ amount: Int64, _ offset: Int, _ direction: ChequeDirection, _ state: PaperState) -> TreasuryItem {
            TreasuryItem(id: UUID(), due: day.adding(days: offset), direction: direction, state: state, remaining: amount)
        }
        let items = [item(3_200_000, 7, .outgoing, .issued), item(4_750_000, 4, .incoming, .inHand),
                     item(10_650_000, 13, .outgoing, .issued), item(900_000, 0, .incoming, .returned)]
        let original = try AccountOutlook(opening: 8_450_000, movements: [], items: items, today: day)
        XCTAssertEqual(original.available7, 5_250_000)
        XCTAssertEqual(original.incoming7, 4_750_000)
        XCTAssertEqual(original.points.first(where: { $0.balance < 0 })?.day.iso, "2026-12-03")
        XCTAssertEqual(original.points.last?.balance, -650_000)
        let changed = try AccountOutlook(opening: 8_450_000, movements: [],
                                         items: items + [item(1_000_000, 12, .incoming, .deposited)], today: day)
        XCTAssertEqual(changed.points.last?.balance, 350_000)
        XCTAssertTrue(changed.points.allSatisfy { $0.balance >= 0 })
        let overdue = try AccountOutlook(opening: 10, movements: [], items: [item(9, -30, .outgoing, .issued)], today: day)
        XCTAssertEqual(overdue.available7, 1)
    }
    func testDepositHasNoBankEffectAndCollectionIsIdempotent() {
        let deposit = op(.deposit)
        let settle = op(.settle, amount: 1_250_000, parent: deposit.id)
        XCTAssertTrue(position([deposit]).bankMovements.isEmpty)
        let projection = position([settle, deposit, deposit, settle])
        XCTAssertEqual(projection.bankMovements, [settle.id: 1_250_000])
        XCTAssertEqual(projection.state, .settled)
        XCTAssertEqual(projection.remaining, 0)
        XCTAssertEqual(position([], initial: .settled).bankMovements, [:])
    }
    func testConcurrentBranchesAreWithheldUntilExplicitResolution() {
        let part = op(.partialBank, amount: 750_000)
        let other = op(.partialCash, amount: 750_000)
        for ordering in [[part, other], [other, part]] {
            let pending = position(ordering)
            XCTAssertEqual(pending.paid, 0)
            XCTAssertEqual(pending.remaining, 1_250_000)
            XCTAssertEqual(pending.conflicts.count, 2)
            XCTAssertTrue(pending.bankMovements.isEmpty)
            let discard = op(.discardConflict, related: other.id, party: "Duplicate receipt")
            let resolved = position(ordering + [discard])
            XCTAssertEqual(resolved.paid, 750_000)
            XCTAssertTrue(resolved.conflicts.isEmpty)
            XCTAssertEqual(resolved.bankMovements[part.id], 750_000)
            let excessive = op(.partialBank, amount: 600_000, parent: part.id)
            XCTAssertEqual(position(ordering + [discard, excessive]).remaining, 500_000)
            XCTAssertEqual(position(ordering + [discard, excessive]).conflicts.map(\.id), [excessive.id])
        }
    }
    func testCashAndEndorsementDoNotCreditBank() {
        let cash = op(.partialCash, amount: 250_000)
        let endorse = op(.endorse, parent: cash.id, party: "Supplier")
        let intermediate = position([cash, endorse])
        XCTAssertEqual(intermediate.holder, "Supplier")
        XCTAssertEqual(intermediate.state, .endorsed)
        XCTAssertEqual(intermediate.remaining, 1_000_000)
        let receipt = op(.acknowledgeEndorsement, amount: 1_000_000, parent: endorse.id)
        let final = position([cash, endorse, receipt])
        XCTAssertTrue(final.bankMovements.isEmpty)
        XCTAssertFalse(final.isOpen)
        XCTAssertEqual(final.paid, 1_250_000)
    }
    func testReturnsPreserveEarlierPaymentsAndReplacementCarriesRemainder() {
        let cash = op(.partialCash, amount: 250_000)
        let returned = op(.markReturned, parent: cash.id)
        let successor = UUID()
        let replace = op(.replace, amount: 1_000_000, parent: returned.id, related: successor)
        let prior = position([cash, returned])
        XCTAssertEqual(prior.state, .returned)
        XCTAssertEqual(prior.paid, 250_000)
        let final = position([replace, returned, cash])
        XCTAssertEqual(final.replacementID, successor)
        XCTAssertEqual(final.legacyStatus, .cancelled)
        XCTAssertEqual(final.state, .replaced)
    }
    func testCurrencyAndOverflowAreRejectedWithoutIncorrectTotals() {
        let usd = LedgerOperation(chequeID: cheque, accountID: account, kind: .settle, day: day, amount: 1_250_000, currency: "USD")
        XCTAssertEqual(position([usd]).conflicts.map(\.id), [usd.id])
        XCTAssertThrowsError(try AccountOutlook(opening: Int64.max, movements: [1], items: [], today: day))
        XCTAssertEqual(try AccountOutlook.sum(Int64.max, [1, -1]), Int64.max)
    }
}
