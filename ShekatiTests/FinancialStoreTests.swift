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
