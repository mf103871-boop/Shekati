import Foundation
import XCTest
import SwiftData
import CoreData
import ShekatiCore
@testable import Shekati

// Frozen build-9 field definitions. Deliberately do not point this fixture at the current
// type: doing so would only test reopening a new store, not a populated old store.
private enum Build9Models {
    @Model final class ChequeRecord {
        var id: UUID = UUID()
        var directionRaw: String = "incoming"
        var statusRaw: String = "pending"
        var amountMinorUnits: Int64 = 0
        var currencyCode: String = ""
        var dueDateISO: String = "2000-01-01"
        var actualDateISO: String?
        var issueDateISO: String?
        var number: String = ""
        var bank: String = ""
        var branch: String = ""
        var party: String = ""
        var accountReference: String = ""
        var notes: String = ""
        var createdAt: Date = Date()
        var manualRank: Int64 = 0
        @Attribute(.externalStorage) var frontImageData: Data?
        @Attribute(.externalStorage) var backImageData: Data?
        var remindersEnabled: Bool = true
        var reminderOffsets: [Int]?
        var reminderHour: Int?
        var reminderMinute: Int?
        var deletedAt: Date?
        init(id: UUID) { self.id = id }
    }
    @Model final class AppConfiguration {
        var id: UUID = UUID()
        var currencyCode: String = ""
        var createdAt: Date = Date()
        init(currencyCode: String) { self.currencyCode = currencyCode }
    }
}

@MainActor
final class Build9MigrationTests: XCTestCase {
    func testPopulatedBuild9StoreMigratesWithoutRenamingEntitiesLosingDataOrImages() throws {
        let oldModel = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(
            for: [Build9Models.ChequeRecord.self, Build9Models.AppConfiguration.self]))
        let newModel = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: [ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self]))
        XCTAssertTrue(Set(oldModel.entities.compactMap(\.name)).isSubset(of: Set(newModel.entities.compactMap(\.name))))
        let oldEntity = try XCTUnwrap(oldModel.entities.first { $0.name?.hasSuffix("ChequeRecord") == true })
        let newEntity = try XCTUnwrap(newModel.entities.first { $0.name == oldEntity.name })
        XCTAssertEqual(Set(newEntity.attributesByName.keys).subtracting(oldEntity.attributesByName.keys), ["bankAccountID", "chequeBookID", "ledgerBaselineStatusRaw", "replacesChequeID"])
        for (name, attribute) in oldEntity.attributesByName {
            XCTAssertEqual(newEntity.attributesByName[name]?.attributeType, attribute.attributeType, name)
            XCTAssertEqual(newEntity.attributesByName[name]?.isOptional, attribute.isOptional, name)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Shekati-build9-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Shekati.store")
        let id = UUID()
        let front = Data(repeating: 0xAB, count: 250_000)
        let back = Data(repeating: 0xCD, count: 200_000)
        try autoreleasepool {
            let schema = Schema([Build9Models.ChequeRecord.self, Build9Models.AppConfiguration.self])
            let configuration = ModelConfiguration("Shekati", schema: schema, url: url, cloudKitDatabase: .none)
            let oldContainer = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(oldContainer); context.autosaveEnabled = false
            let record = Build9Models.ChequeRecord(id: id)
            record.directionRaw = "outgoing"; record.statusRaw = "settled"
            record.amountMinorUnits = 12_345; record.currencyCode = "JOD"
            record.dueDateISO = "2026-10-20"; record.actualDateISO = "2026-10-21"; record.issueDateISO = "2026-10-01"
            record.number = "000123"; record.bank = "Demo bank"; record.branch = "عمّان"
            record.party = "شيك تجريبي"; record.accountReference = "000456"; record.notes = "Migration fixture"
            record.createdAt = Date(timeIntervalSince1970: 1_700_000_000); record.manualRank = 17
            record.frontImageData = front; record.backImageData = back
            record.remindersEnabled = false; record.reminderOffsets = [7, 0]; record.reminderHour = 8; record.reminderMinute = 30
            let deleted = Build9Models.ChequeRecord(id: UUID())
            deleted.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
            deleted.number = "000111"
            context.insert(deleted)
            context.insert(record); context.insert(Build9Models.AppConfiguration(currencyCode: "JOD"))
            try context.save()
        }
        try autoreleasepool {
            let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
            let configuration = ModelConfiguration("Shekati", schema: schema, url: url, cloudKitDatabase: .none)
            let newContainer = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(newContainer)
            let fetched = try context.fetch(FetchDescriptor<ChequeRecord>())
            XCTAssertEqual(fetched.count, 2)
            XCTAssertNotNil(fetched.first(where: { $0.number == "000111" })?.deletedAt)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEventRecord>()), 0)
            let loaded = try XCTUnwrap(fetched.first(where: { $0.id == id }))
            XCTAssertNil(loaded.bankAccountID)
            XCTAssertEqual(loaded.id, id); XCTAssertNil(loaded.deletedAt); XCTAssertTrue(loaded.isActive)
            XCTAssertEqual(loaded.number, "000123"); XCTAssertEqual(loaded.amountMinorUnits, 12_345)
            XCTAssertEqual(loaded.directionRaw, "outgoing"); XCTAssertEqual(loaded.statusRaw, "settled")
            XCTAssertEqual(loaded.dueDateISO, "2026-10-20"); XCTAssertEqual(loaded.actualDateISO, "2026-10-21")
            XCTAssertEqual(loaded.issueDateISO, "2026-10-01"); XCTAssertEqual(loaded.currencyCode, "JOD")
            XCTAssertEqual(loaded.bank, "Demo bank"); XCTAssertEqual(loaded.branch, "عمّان")
            XCTAssertEqual(loaded.party, "شيك تجريبي"); XCTAssertEqual(loaded.accountReference, "000456")
            XCTAssertEqual(loaded.notes, "Migration fixture"); XCTAssertEqual(loaded.manualRank, 17)
            XCTAssertEqual(loaded.frontImageData, front); XCTAssertEqual(loaded.backImageData, back)
            XCTAssertFalse(loaded.remindersEnabled); XCTAssertEqual(loaded.reminderOffsets, [7, 0])
            XCTAssertEqual(loaded.reminderHour, 8); XCTAssertEqual(loaded.reminderMinute, 30)
            XCTAssertEqual(try context.fetch(FetchDescriptor<AppConfiguration>()).first?.currencyCode, "JOD")
            loaded.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
            try context.save()
        }
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Shekati", schema: schema, url: url, cloudKitDatabase: .none)
        ])
        let reopened = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ChequeRecord>()).first(where: { $0.id == id }))
        XCTAssertEqual(reopened.id, id); XCTAssertNotNil(reopened.deletedAt)
        XCTAssertEqual(reopened.frontImageData, front)
    }
}
