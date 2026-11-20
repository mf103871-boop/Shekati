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
        var olderDeleted = ChequeBackupEntry(snapshot: before.records[0].snapshot)
        olderDeleted.deletedAt = Date()
        let oldTrash = ChequeBackupPayload(currencyCode: "JOD", records: [olderDeleted])
        try ChequeTransferService.restore(oldTrash, into: target.mainContext, replaceExisting: true)
        XCTAssertNil(live.deletedAt)
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

    func testLegacyJODSettlementPreservesUSDAccountFreeQuotaAuditAndExport() throws {
        let source = try store()
        let context = source.mainContext
        try BankingLedger.addAccount(name: "Only USD", currency: "USD", opening: 84_501, isPlus: false, context: context)
        let day = LocalDay.today.adding(days: -1)
        let original = ChequeSnapshot(direction: .outgoing, amountMinorUnits: 125_001, currencyCode: "JOD",
                                      dueDate: day, issueDate: day.adding(days: -5), number: "004182", notes: "Original note")
        let v1 = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(snapshot: original)])
        try ChequeTransferService.restore(v1, into: context)
        let cheque = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeRecord>()).first)
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<BankAccountRecord>()).first)
        let book = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeBookRecord>()).first)
        func entry() -> ChequeBackupEntry {
            ChequeBackupEntry(snapshot: ChequeSnapshot(direction: .incoming, amountMinorUnits: 1, currencyCode: "USD", dueDate: day))
        }
        try ChequeTransferService.importCSV(ChequeBackupPayload(currencyCode: "USD", records: (0..<9).map { _ in entry() }), into: context, isPlus: false)
        let extra = ChequeBackupPayload(currencyCode: "USD", records: [entry()])
        XCTAssertThrowsError(try ChequeTransferService.importCSV(extra, into: context, isPlus: false))
        XCTAssertThrowsError(try BankingLedger.addAccount(name: "JOD", currency: "JOD", opening: 0, isPlus: false, context: context))
        XCTAssertThrowsError(try BankingLedger.link(record: cheque, account: account, book: book, context: context))
        let id = UUID()
        let reason = "Owner verified receipt 24"
        func settle(_ op: UUID? = nil, on date: LocalDay? = nil, note: String? = nil, amount: Int64 = 125_001) throws {
            try BankingLedger.settleHistorically(cheque, operationID: op ?? id, amount: amount, currency: "JOD", day: date ?? day,
                                                 reason: note ?? reason, isPlus: false, context: context)
        }
        XCTAssertFalse(BankingLedger.canSettleHistorically(cheque, accounts: [], events: [], isPlus: false))
        XCTAssertFalse(BankingLedger.canSettleHistorically(cheque, accounts: [account], events: [], isPlus: true))
        XCTAssertFalse(BankingLedger.canSettleHistorically(cheque, accounts: [BankAccountRecord(name: "JOD", currencyCode: "JOD", openingMinor: 0)], events: [], isPlus: false))
        XCTAssertThrowsError(try settle(on: .today.adding(days: 1)))
        XCTAssertThrowsError(try settle(on: day.adding(days: -6)))
        XCTAssertThrowsError(try settle(note: " "))
        XCTAssertThrowsError(try settle(amount: 125))
        try settle()
        try settle()
        XCTAssertThrowsError(try settle(note: "Different reason"))
        XCTAssertThrowsError(try settle(UUID()))
        XCTAssertNil(cheque.bankAccountID)
        XCTAssertEqual(cheque.actualDate, day)
        XCTAssertEqual(cheque.status, .settled)
        XCTAssertEqual(cheque.notes, original.notes)
        let journal = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let current = BankingLedger.position(for: cheque, events: journal)
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(current.accepted.first?.party, reason)
        XCTAssertEqual(current.accepted.first?.currency, "JOD")
        XCTAssertEqual(current.paid, 125_001)
        XCTAssertEqual(current.remaining, 0)
        XCTAssertTrue(current.bankMovements.isEmpty)
        XCTAssertTrue(BankingLedger.reminderInputs(records: [cheque], events: journal).isEmpty)
        let usd = try BankingLedger.outlook(account: account, records: [cheque], events: journal, today: .today)
        XCTAssertEqual(usd.recorded, 84_501)
        XCTAssertEqual(usd.available7, 84_501)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BankAccountRecord>()), 1)
        XCTAssertEqual(try ChequeTransferService.importCSV(extra, into: context, isPlus: false), 1)
        XCTAssertThrowsError(try ChequeTransferService.importCSV(ChequeBackupPayload(currencyCode: "USD", records: [entry()]), into: context, isPlus: false))

        let rows = ChequeReportRows(ids: [cheque.id], records: [cheque], events: journal)
        let csv = ChequeCSV.export(rows.originals, historicalReasons: rows.historicalReasons)
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        for field in ["historical_settlement_reason", reason, "125.001", "JOD", "004182", day.iso, "settled", original.notes] {
            XCTAssertTrue(text.contains(field), field)
        }
        let archive = try BankingArchive(accounts: [account], books: [book], events: journal)
        let complete = ChequeBackupPayload(version: 2, currencyCode: "USD", records: [ChequeBackupEntry(record: cheque)], banking: archive)
        let password = "Public-fixture-password"
        let exported = try EncryptedBackup.encrypt(complete, password: password)
        let destination = try store()
        let restored = destination.mainContext
        try ChequeTransferService.restore(EncryptedBackup.decrypt(exported, password: password), into: restored)
        try ChequeTransferService.restore(v1, into: restored, replaceExisting: true)
        let recovered = try XCTUnwrap(restored.fetch(FetchDescriptor<ChequeRecord>()).first)
        let events = try restored.fetch(FetchDescriptor<LedgerEventRecord>())
        XCTAssertEqual(BankingLedger.position(for: recovered, events: events).accepted, current.accepted)
        XCTAssertEqual(recovered.actualDate, day)
        XCTAssertEqual(recovered.status, .settled)
        let attestation = try XCTUnwrap(current.accepted.first)
        try BankingLedger.dismissConflict(attestation, reason: "Receipt belongs to another paper", record: recovered, context: restored)
        let corrected = try restored.fetch(FetchDescriptor<LedgerEventRecord>())
        XCTAssertEqual(recovered.status, .pending)
        XCTAssertNil(recovered.actualDate)
        XCTAssertEqual(corrected.count, 2)
        XCTAssertThrowsError(try BankingLedger.settleHistorically(recovered, operationID: id, amount: 125_001, currency: "JOD", day: day, reason: reason, isPlus: false, context: restored))
        let corrections = try BankingArchive(accounts: [account], books: [book], events: corrected)
        try corrections.validate(records: [ChequeBackupEntry(record: recovered)])
    }

    func testConcurrentBankCollectionAndHistoricalAttestationRequireReviewInEitherMergeOrder() throws {
        let original = ChequeSnapshot(direction: .incoming, status: .returned, amountMinorUnits: 123_456, currencyCode: "JOD", dueDate: .today)
        let historical = try store(), bank = try store()
        let v1 = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(snapshot: original)])
        for container in [historical, bank] { try ChequeTransferService.restore(v1, into: container.mainContext) }
        try BankingLedger.addAccount(name: "USD", currency: "USD", opening: 789, isPlus: false, context: historical.mainContext)
        let historicalCheque = try XCTUnwrap(historical.mainContext.fetch(FetchDescriptor<ChequeRecord>()).first)
        let bankCheque = try XCTUnwrap(bank.mainContext.fetch(FetchDescriptor<ChequeRecord>()).first)
        try BankingLedger.settleHistorically(historicalCheque, operationID: UUID(), amount: original.amountMinorUnits, currency: "JOD",
                                             day: .today.adding(days: -1), reason: "Previously resolved", isPlus: false, context: historical.mainContext)
        try BankingLedger.addAccount(name: "JOD", currency: "JOD", opening: 1_000_000, isPlus: false, context: bank.mainContext)
        let account = try XCTUnwrap(bank.mainContext.fetch(FetchDescriptor<BankAccountRecord>()).first)
        try BankingLedger.link(record: bankCheque, account: account, book: nil, context: bank.mainContext)
        try BankingLedger.perform(.settle, for: bankCheque, day: .today, expectedParent: nil, isPlus: false, context: bank.mainContext)
        func payload(_ context: ModelContext) throws -> ChequeBackupPayload {
            let accounts = try context.fetch(FetchDescriptor<BankAccountRecord>())
            let books = try context.fetch(FetchDescriptor<ChequeBookRecord>())
            let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
            let archive = try BankingArchive(accounts: accounts, books: books, events: events)
            return ChequeBackupPayload(version: 2, currencyCode: "USD", records: try context.fetch(FetchDescriptor<ChequeRecord>()).map(ChequeBackupEntry.init(record:)), banking: archive)
        }
        let a = try payload(historical.mainContext), b = try payload(bank.mainContext)
        for (first, second, dismissHistorical) in [(a, b, true), (b, a, false)] {
            let merged = try store(), context = merged.mainContext
            try ChequeTransferService.restore(first, into: context)
            try ChequeTransferService.restore(second, into: context)
            let cheque = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeRecord>()).first)
            let accounts = try context.fetch(FetchDescriptor<BankAccountRecord>())
            let usd = try XCTUnwrap(accounts.first(where: { $0.currencyCode == "USD" }))
            let jod = try XCTUnwrap(accounts.first(where: { $0.currencyCode == "JOD" }))
            XCTAssertEqual(cheque.bankAccountID, jod.id)
            var events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
            let conflicted = BankingLedger.position(for: cheque, events: events)
            XCTAssertEqual(conflicted.conflicts.count, 2)
            XCTAssertTrue(conflicted.bankMovements.isEmpty)
            XCTAssertThrowsError(try BankingLedger.outlook(account: jod, records: [cheque], events: events, today: .today))
            XCTAssertEqual(try BankingLedger.outlook(account: usd, records: [cheque], events: events, today: .today).recorded, 789)
            let rejected = try XCTUnwrap(conflicted.conflicts.first(where: { $0.kind == (dismissHistorical ? .historicalSettlement : .settle) }))
            try BankingLedger.dismissConflict(rejected, reason: "Verified statement", record: cheque, context: context)
            events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
            XCTAssertEqual(BankingLedger.position(for: cheque, events: events).conflicts.count, 0)
            XCTAssertEqual(cheque.status, .settled)
            XCTAssertEqual(cheque.actualDate, dismissHistorical ? .today : .today.adding(days: -1))
            XCTAssertEqual(try BankingLedger.outlook(account: jod, records: [cheque], events: events, today: .today).recorded,
                           dismissHistorical ? 1_123_456 : 1_000_000)
            let resolved = try payload(context)
            let reopened = try store()
            try ChequeTransferService.restore(resolved, into: reopened.mainContext)
            XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<LedgerEventRecord>()), 3)
        }
    }

    func testReportRetainsSettlementDateForAnAlreadyClosedLegacyBaseline() throws {
        let day = LocalDay.today.adding(days: -80)
        let settled = ChequeSnapshot(direction: .incoming, status: .settled, amountMinorUnits: 100, currencyCode: "USD",
                                     dueDate: day, actualDate: day, number: "009")
        let cheque = ChequeRecord(snapshot: settled)
        cheque.ledgerBaselineStatusRaw = PaperState.settled.rawValue
        let rows = ChequeReportRows(ids: [cheque.id], records: [cheque], events: [])
        let csv = ChequeCSV.export(rows.originals, historicalReasons: rows.historicalReasons)
        XCTAssertTrue(rows.historicalReasons.isEmpty)
        let review = try ChequeCSV.preview(csv, currencyCode: "USD", existing: [])
        XCTAssertTrue(review.issues.isEmpty)
        XCTAssertEqual(review.rows.first?.snapshot.actualDate, day)
    }
}
