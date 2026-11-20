import XCTest
import SwiftData
import CryptoKit
import UIKit
import ShekatiCore
@testable import Shekati

/// The exact same immutable file is distributed for a one-iPhone in-place upgrade.
@MainActor
final class OnePhoneTrainingBackupTests: XCTestCase {
    private let password = "Shekati-Demo-2026"
    private let archiveHash = "bd6c1333d6ae6bf29b1e9fe0a338cb3b9bf51426f190e87c07ba25bbd7ea631f"
    private let frontHash = "481cfe7f33e233900435fd26fff006bee047542a1c965fdea1f45a422ea8b17c"
    private let backHash = "9450f838068056053d6d9684abed7e64a63ce24d027fe4b328df5d6a066958fc"

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeIsolatedStore() throws -> ModelContainer {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self,
                             ChequeBookRecord.self, LedgerEventRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testBuild9TrainingArchiveRestoresUpgradesAndReplaysWithoutDuplicating() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Build9-Training-JOD", withExtension: "shekati"))
        let contents = try Data(contentsOf: url)
        XCTAssertEqual(digest(contents), archiveHash)
        let legacy = try EncryptedBackup.decrypt(contents, password: password)
        XCTAssertEqual(legacy.version, 1)
        XCTAssertNil(legacy.banking)
        XCTAssertEqual(legacy.currencyCode, "JOD")
        let global = try XCTUnwrap(legacy.globalReminders)
        XCTAssertEqual(global.offsets, [7, 3, 1, 0])
        XCTAssertEqual(global.hour, 9)
        XCTAssertEqual(global.minute, 15)
        XCTAssertTrue(global.hideDetails)
        XCTAssertTrue(global.dailySummary)
        let oldStore = try makeIsolatedStore()
        let imported = oldStore.mainContext
        XCTAssertEqual(try ChequeTransferService.restore(legacy, into: imported), 6)
        try verifyStore(imported)

        let archive = try BankingArchive(accounts: [], books: [], events: [])
        let updated = ChequeBackupPayload(version: 2, currencyCode: legacy.currencyCode,
                                          records: try imported.fetch(FetchDescriptor<ChequeRecord>()).map { ChequeBackupEntry(record: $0) },
                                          globalReminders: global, banking: archive)
        let renewed = try EncryptedBackup.encrypt(updated, password: password)
        let decoded = try EncryptedBackup.decrypt(renewed, password: password)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.globalReminders, global)
        XCTAssertEqual(decoded.banking, archive)
        let destination = try makeIsolatedStore()
        XCTAssertEqual(try ChequeTransferService.restore(decoded, into: destination.mainContext), 6)
        XCTAssertEqual(try ChequeTransferService.restore(decoded, into: destination.mainContext), 0)
        try verifyStore(destination.mainContext)
        let originalEntries = Dictionary(uniqueKeysWithValues: legacy.records.map { ($0.snapshot.id, $0.normalized) })
        let restoredEntries = try destination.mainContext.fetch(FetchDescriptor<ChequeRecord>()).map { ChequeBackupEntry(record: $0) }
        for restored in restoredEntries {
            XCTAssertEqual(originalEntries[restored.snapshot.id], restored)
        }
    }

    private func verifyStore(_ context: ModelContext) throws {
        let stored = try context.fetch(FetchDescriptor<ChequeRecord>())
        let live = stored.filter(\.isActive)
        XCTAssertEqual(Set(stored.map(\.number)), ["004182", "000207", "007309", "000013", "000014", "000900"])
        XCTAssertEqual(stored.count, 6)
        XCTAssertEqual(live.count, 5)
        XCTAssertTrue(stored.allSatisfy { $0.currencyCode == "JOD" && $0.bankAccountID == nil })
        let open = live.filter { $0.snapshot.isOutstanding }
        XCTAssertEqual(open.count, 3)
        XCTAssertEqual(open.filter { $0.direction == .incoming }.reduce(Int64(0)) { $0 + $1.amountMinorUnits }, 1_650_200)
        XCTAssertEqual(open.filter { $0.direction == .outgoing }.reduce(Int64(0)) { $0 + $1.amountMinorUnits }, 3_200_050)
        let scanned = try XCTUnwrap(live.first { $0.number == "004182" })
        XCTAssertEqual(scanned.dueDateISO, "2026-11-24")
        XCTAssertEqual(scanned.reminderOffsets, [7, 3, 1, 0])
        XCTAssertEqual(scanned.reminderHour, 9)
        XCTAssertEqual(scanned.reminderMinute, 15)
        let front = try XCTUnwrap(scanned.frontImageData), back = try XCTUnwrap(scanned.backImageData)
        XCTAssertEqual(digest(front), frontHash)
        XCTAssertEqual(digest(back), backHash)
        XCTAssertEqual(UIImage(data: front)?.cgImage?.width, 320)
        XCTAssertEqual(UIImage(data: back)?.cgImage?.height, 140)
        XCTAssertEqual(live.first { $0.number == "000013" }?.actualDateISO, "2026-11-11")
        XCTAssertEqual(live.first { $0.number == "000014" }?.actualDateISO, "2026-11-12")
        XCTAssertEqual(live.first { $0.number == "000207" }?.status, .returned)
        let tombstone = try XCTUnwrap(stored.first { $0.number == "000900" }?.deletedAt)
        XCTAssertEqual(tombstone.timeIntervalSince1970, 1795086000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEventRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BankAccountRecord>()), 0)
    }
}
