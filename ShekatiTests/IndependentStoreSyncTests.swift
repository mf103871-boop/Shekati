import SwiftData
import XCTest
import ShekatiCore
@testable import Shekati

/// Each replica has an independent SwiftData container. Transport replay is explicit
/// here so suspension, out-of-order delivery and retransmission are reproducible.
@MainActor
final class IndependentStoreSyncTests: XCTestCase {
    private struct Replica {
        let store: ModelContainer
        let account: BankAccountRecord
        let cheque: ChequeRecord
    }

    private func replica(accountID: UUID, chequeID: UUID) throws -> Replica {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let store = try ModelContainer(for: schema, configurations: [config])
        let account = BankAccountRecord(id: accountID, name: "Replicated account", currencyCode: "JOD", openingMinor: 0)
        let cheque = ChequeRecord(snapshot: ChequeSnapshot(id: chequeID, direction: .incoming, amountMinorUnits: 100_000, currencyCode: "JOD", dueDate: .today, number: "004182", party: "Fixture"))
        cheque.bankAccountID = accountID
        store.mainContext.insert(account)
        store.mainContext.insert(cheque)
        try store.mainContext.save()
        return Replica(store: store, account: account, cheque: cheque)
    }

    private func history(_ replica: Replica) throws -> [LedgerEventRecord] {
        try replica.store.mainContext.fetch(FetchDescriptor<LedgerEventRecord>())
    }

    func testConcurrentOfflineSettlementsConvergeAfterExplicitConflictResolution() throws {
        let accountID = UUID(), chequeID = UUID()
        let first = try replica(accountID: accountID, chequeID: chequeID)
        let second = try replica(accountID: accountID, chequeID: chequeID)
        for client in [first, second] {
            try BankingLedger.perform(.partialBank, for: client.cheque, amount: 70_000, day: .today, expectedParent: nil, isPlus: true, context: client.store.mainContext)
        }
        let a = try XCTUnwrap(history(first).first?.operation)
        let b = try XCTUnwrap(history(second).first?.operation)
        for (client, remote) in [(first, b), (second, a)] {
            client.store.mainContext.insert(LedgerEventRecord(remote))
            try client.store.mainContext.save()
            let ops = try history(client)
            XCTAssertEqual(BankingLedger.position(for: client.cheque, events: ops).conflicts.count, 2)
            XCTAssertThrowsError(try BankingLedger.outlook(account: client.account, records: [client.cheque], events: ops, today: .today))
        }

        try BankingLedger.dismissConflict(b, reason: "Duplicate settlement verified", record: first.cheque, context: first.store.mainContext)
        let correction = try XCTUnwrap(history(first).compactMap(\.operation).first { $0.kind == .discardConflict })
        second.store.mainContext.insert(LedgerEventRecord(correction))
        second.store.mainContext.insert(LedgerEventRecord(a))
        try second.store.mainContext.save()
        for client in [first, second] {
            let ops = try history(client)
            let position = BankingLedger.position(for: client.cheque, events: ops)
            XCTAssertTrue(position.conflicts.isEmpty)
            XCTAssertEqual(position.remaining, 30_000)
            XCTAssertEqual(try BankingLedger.outlook(account: client.account, records: [client.cheque], events: ops, today: .today).recorded, 70_000)
        }
    }
}

