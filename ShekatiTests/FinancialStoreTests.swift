import XCTest
import SwiftData
import ShekatiCore
@testable import Shekati

@MainActor
final class FinancialStoreTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    func testRestoreAndReplacementAccountForEarlierPaymentExactlyOnce() throws {
        let container = try store()
        let context = container.mainContext
        try BankingLedger.addAccount(name: "Operating", currency: "JOD", opening: 8_450_000, isPlus: false, context: context)
        XCTAssertThrowsError(try BankingLedger.addAccount(name: "Second", currency: "JOD", opening: 0, isPlus: false, context: context))
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<BankAccountRecord>()).first)
        let book = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeBookRecord>()).first)
        let cheque = ChequeRecord(snapshot: ChequeSnapshot(direction: .outgoing, amountMinorUnits: 3_200_000, currencyCode: "JOD",
                                                             dueDate: .today, number: "004182", party: "Supplier"))
        context.insert(cheque)
        try BankingLedger.link(record: cheque, account: account, book: book, context: context)
        try BankingLedger.perform(.partialBank, for: cheque, amount: 1_000_000, day: .today, expectedParent: nil, isPlus: true, context: context)
        let partial = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEventRecord>()).first)
        try BankingLedger.perform(.replace, for: cheque, day: .today, replacementNumber: "004183", replacementDue: .today,
                                  expectedParent: partial.id, isPlus: true, context: context)
        let all = try context.fetch(FetchDescriptor<ChequeRecord>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.replacesChequeID == cheque.id })?.amountMinorUnits, 2_200_000)
        let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let outlook = try BankingLedger.outlook(account: account, records: all, events: events, today: .today)
        XCTAssertEqual(outlook.recorded, 7_450_000)
        XCTAssertEqual(outlook.available7, 5_250_000)

        let archive = try BankingArchive(accounts: [account], books: [book], events: events)
        let payload = ChequeBackupPayload(version: 2, currencyCode: "JOD", records: all.map(ChequeBackupEntry.init(record:)), banking: archive)
        let target = try store()
        let destination = target.mainContext
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: destination), 2)
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: destination), 0)
        let restored = try XCTUnwrap(destination.fetch(FetchDescriptor<BankAccountRecord>()).first)
        let restoredOutlook = try BankingLedger.outlook(account: restored, records: destination.fetch(FetchDescriptor<ChequeRecord>()),
                                                       events: destination.fetch(FetchDescriptor<LedgerEventRecord>()), today: .today)
        XCTAssertEqual(restoredOutlook.recorded, outlook.recorded)
        XCTAssertEqual(restoredOutlook.available7, outlook.available7)
    }

    func testBackupWithOnlyFinancialUpdatesCanBeReviewedAndRestoredWithoutReopening() throws {
        let source = try store()
        let target = try store()
        let context = source.mainContext
        try BankingLedger.addAccount(name: "Current", currency: "JOD", opening: 8_450_000, isPlus: false, context: context)
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<BankAccountRecord>()).first)
        let book = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeBookRecord>()).first)
        func payload() throws -> ChequeBackupPayload {
            let archive = try BankingArchive(accounts: [account], books: [book], events: context.fetch(FetchDescriptor<LedgerEventRecord>()))
            return ChequeBackupPayload(version: 2, currencyCode: "JOD", records: try context.fetch(FetchDescriptor<ChequeRecord>()).map(ChequeBackupEntry.init(record:)), banking: archive)
        }
        let onlyAccount = try payload()
        let preview = try ChequeTransferService.preview(onlyAccount, existing: [], context: target.mainContext)
        XCTAssertEqual(preview.newAccounts, 1)
        XCTAssertEqual(preview.newBooks, 1)
        XCTAssertTrue(preview.hasBankingChanges)
        try ChequeTransferService.restore(onlyAccount, into: target.mainContext)

        let cheque = ChequeRecord(snapshot: ChequeSnapshot(direction: .incoming, amountMinorUnits: 1_000_000, currencyCode: "JOD", dueDate: .today, number: "004182"))
        context.insert(cheque)
        try BankingLedger.link(record: cheque, account: account, book: nil, context: context)
        let before = try payload()
        try ChequeTransferService.restore(before, into: target.mainContext)
        let live = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<ChequeRecord>()).first)
        try BankingLedger.perform(.partialBank, for: cheque, amount: 200_000, day: .today, expectedParent: nil, isPlus: true, context: context)
        let partial = try payload()
        let newPayment = try ChequeTransferService.preview(partial, existing: [live], context: target.mainContext)
        XCTAssertEqual(newPayment.newCount, 0)
        XCTAssertEqual(newPayment.newOperations, 1)
        XCTAssertTrue(newPayment.hasBankingChanges)
        try ChequeTransferService.restore(partial, into: target.mainContext)
        let journal = try target.mainContext.fetch(FetchDescriptor<LedgerEventRecord>())
        XCTAssertEqual(BankingLedger.reminderInputs(records: [live], events: journal).first?.snapshot.amountMinorUnits, 800_000)
        try BankingLedger.perform(.settle, for: live, day: .today, expectedParent: journal.first?.id, isPlus: false, context: target.mainContext)
        try ChequeTransferService.restore(before, into: target.mainContext, replaceExisting: true)
        XCTAssertEqual(live.status, .settled)
        XCTAssertEqual(live.actualDate, .today)
        let events = try target.mainContext.fetch(FetchDescriptor<LedgerEventRecord>())
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(BankingLedger.reminderInputs(records: [live], events: events).isEmpty)
    }

    func testProjectedReportUsesSameThreeDecimalAmountsAsTheAccountForecast() throws {
        let today = LocalDay.today
        func item(_ direction: ChequeDirection, _ amount: Int64, _ due: Int) -> TreasuryItem {
            TreasuryItem(id: UUID(), due: today.adding(days: due), direction: direction,
                         state: direction == .incoming ? .inHand : .issued, remaining: amount)
        }
        let base = [item(.outgoing, 3_200_000, 5), item(.incoming, 4_750_000, 7), item(.outgoing, 10_650_000, 13)]
        for (extra, final) in [([], Int64(-650_000)), ([item(.incoming, 1_000_000, 11)], 350_000)] {
            let outlook = try AccountOutlook(opening: 8_450_000, movements: [], items: base + extra, today: today)
            let rows = CashFlowReport.rows(for: outlook, currency: "JOD", language: .english)
            let render: (Int64) -> String = { DisplayFormatting.amount(minorUnits: $0, currencyCode: "JOD", locale: AppLanguage.english.locale) }
            XCTAssertEqual(outlook.available7, 5_250_000)
            XCTAssertEqual(rows[3].amount, render(5_250_000))
            XCTAssertEqual(rows.last?.amount, render(final))
            let account = BankAccountRecord(name: "Current", currencyCode: "JOD", openingMinor: 8_450_000)
            XCTAssertTrue(CashFlowReport.generate(outlook, account: account, language: .arabic).starts(with: Data("%PDF-".utf8)))
        }
    }

    func testReconciliationRechecksDisplayedBalanceAndPersistsZeroCheckpoints() throws {
        let container = try store()
        let context = container.mainContext
        let account = BankAccountRecord(name: "Test", currencyCode: "JPY", openingMinor: 100)
        context.insert(account); try context.save()
        try BankingLedger.reconcile(account, statement: -200, expected: 100, context: context)
        XCTAssertThrowsError(try BankingLedger.reconcile(account, statement: 300, expected: 100, context: context))
        try BankingLedger.reconcile(account, statement: -200, expected: -200, context: context)
        let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        XCTAssertEqual(try BankingLedger.adjustments(account: account, events: events).map(\.amount), [-300, 0])
        XCTAssertEqual(try BankingLedger.outlook(account: account, records: [], events: events, today: .today).recorded, -200)
    }

    func testCSVConsultsLiveFreeLimitWhileBackupRecoveryRemainsAvailable() throws {
        let container = try store()
        let context = container.mainContext
        func entry() -> ChequeBackupEntry {
            ChequeBackupEntry(snapshot: ChequeSnapshot(direction: .incoming, amountMinorUnits: 1, currencyCode: "JPY", dueDate: .today))
        }
        let initial = ChequeBackupPayload(currencyCode: "JPY", records: (0..<9).map { _ in entry() })
        XCTAssertEqual(try ChequeTransferService.importCSV(initial, into: context, isPlus: false), 9)
        let extra = ChequeBackupPayload(currencyCode: "JPY", records: [entry(), entry()])
        XCTAssertThrowsError(try ChequeTransferService.importCSV(extra, into: context, isPlus: false))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChequeRecord>()), 9)
        XCTAssertEqual(try ChequeTransferService.restore(extra, into: context), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChequeRecord>()), 11)
    }
}
