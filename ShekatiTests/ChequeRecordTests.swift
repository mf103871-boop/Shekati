import Foundation
import XCTest
import SwiftData
import ShekatiCore
@testable import Shekati

@MainActor
final class ChequeRecordTests: XCTestCase {
    func testSnapshotMappingPreservesLeadingZerosArabicTextAndCivilDates() throws {
        let original = ChequeSnapshot(
            direction: .incoming, status: .settled, amountMinorUnits: 12_345,
            currencyCode: "JOD", dueDate: try day("2026-10-20"),
            actualDate: try day("2026-10-21"), issueDate: try day("2026-10-01"),
            number: "000123", bank: "البنك العربي", branch: "عمّان",
            party: "محمود", accountReference: "001234", notes: "شيك تجريبي",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), manualRank: 7
        )
        let record = ChequeRecord(snapshot: original)

        XCTAssertEqual(record.snapshot, original)
        XCTAssertEqual(record.number, "000123")
        XCTAssertEqual(record.accountReference, "001234")
        XCTAssertEqual(record.dueDateISO, "2026-10-20")
        XCTAssertEqual(record.actualDateISO, "2026-10-21")
        XCTAssertEqual(record.issueDateISO, "2026-10-01")
    }

    func testOptionalDatesStayAbsentInsteadOfBecomingToday() throws {
        let original = ChequeSnapshot(direction: .outgoing, amountMinorUnits: 1_001,
                                      currencyCode: "JOD", dueDate: try day("2026-11-01"))
        let record = ChequeRecord(snapshot: original)

        XCTAssertNil(record.issueDateISO)
        XCTAssertNil(record.actualDateISO)
        XCTAssertNil(record.issueDate)
        XCTAssertNil(record.actualDate)
        XCTAssertEqual(record.snapshot, original)
    }

    func testUpdatingSnapshotKeepsIdentityImagesAndReminderConfiguration() throws {
        let original = ChequeSnapshot(direction: .incoming, amountMinorUnits: 10_000,
                                      currencyCode: "JOD", dueDate: try day("2026-10-20"), number: "000987")
        let front = Data([1, 2, 3, 4])
        let back = Data([5, 6, 7])
        let record = ChequeRecord(snapshot: original, frontImageData: front, backImageData: back,
                                  remindersEnabled: false, reminderOffsets: [14, 3, 0],
                                  reminderHour: 8, reminderMinute: 30)
        var updated = original
        updated.id = UUID() // A snapshot update cannot replace the persistent record's identity.
        updated.status = .settled
        updated.amountMinorUnits = 20_500
        updated.actualDate = try day("2026-10-19")
        updated.party = "أحمد"
        updated.manualRank = 18

        record.update(from: updated)

        XCTAssertEqual(record.id, original.id)
        XCTAssertEqual(record.status, .settled)
        XCTAssertEqual(record.amountMinorUnits, 20_500)
        XCTAssertEqual(record.actualDate?.iso, "2026-10-19")
        XCTAssertEqual(record.party, "أحمد")
        XCTAssertEqual(record.manualRank, 18)
        XCTAssertEqual(record.frontImageData, front)
        XCTAssertEqual(record.backImageData, back)
        XCTAssertFalse(record.remindersEnabled)
        XCTAssertEqual(record.reminderOffsets, [14, 3, 0])
        XCTAssertEqual(record.reminderHour, 8)
        XCTAssertEqual(record.reminderMinute, 30)
    }

    func testInMemoryStoreSavesReloadsModifiesAndDeletesCheque() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let snapshot = ChequeSnapshot(
            direction: .outgoing, amountMinorUnits: 89_125, currencyCode: "JOD",
            dueDate: try day("2026-12-10"), issueDate: try day("2026-10-10"),
            number: "000004", bank: "بنك", party: "المستفيد"
        )
        let front = Data([11, 12, 13])
        let back = Data([14, 15])
        writer.insert(ChequeRecord(snapshot: snapshot, frontImageData: front, backImageData: back,
                                  remindersEnabled: true, reminderOffsets: [7, 0], reminderHour: 10, reminderMinute: 15))
        try writer.save()

        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<ChequeRecord>()).first)
        XCTAssertEqual(saved.snapshot, snapshot)
        XCTAssertEqual(saved.frontImageData, front)
        XCTAssertEqual(saved.backImageData, back)
        XCTAssertEqual(saved.reminderOffsets, [7, 0])
        XCTAssertEqual(saved.reminderHour, 10)
        XCTAssertEqual(saved.reminderMinute, 15)

        saved.status = .returned
        saved.amountMinorUnits = 90_000
        saved.dueDate = try day("2027-01-05")
        saved.remindersEnabled = false
        saved.backImageData = nil
        try reader.save()

        let reloader = ModelContext(container)
        reloader.autosaveEnabled = false
        let modified = try XCTUnwrap(reloader.fetch(FetchDescriptor<ChequeRecord>()).first)
        XCTAssertEqual(modified.id, snapshot.id)
        XCTAssertEqual(modified.status, .returned)
        XCTAssertEqual(modified.amountMinorUnits, 90_000)
        XCTAssertEqual(modified.dueDate.iso, "2027-01-05")
        XCTAssertFalse(modified.remindersEnabled)
        XCTAssertEqual(modified.frontImageData, front)
        XCTAssertNil(modified.backImageData)

        reloader.delete(modified)
        try reloader.save()
        let afterDelete = ModelContext(container)
        XCTAssertTrue(try afterDelete.fetch(FetchDescriptor<ChequeRecord>()).isEmpty)
    }

    func testFilteredDragPersistsHiddenPositionsInBothSortDirections() throws {
        for ascending in [true, false] {
            let container = try makeContainer()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let due = try day("2026-11-01")
            let original = (0..<4).map { index in
                ChequeRecord(snapshot: ChequeSnapshot(
                    direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                    amountMinorUnits: Int64(index + 1) * 1_000,
                    currencyCode: "JOD", dueDate: due,
                    number: String(format: "%04d", index), manualRank: Int64(index)
                ))
            }
            original.forEach { context.insert($0) }
            try context.save()
            let global = ChequeListEngine.filteredAndSorted(
                cheques: original.map(\.snapshot), filter: .init(), sort: .manual, ascending: ascending
            ).map(\.id)
            let visible = ChequeListEngine.filteredAndSorted(
                cheques: original.map(\.snapshot), filter: .init(direction: .incoming),
                sort: .manual, ascending: ascending
            ).map(\.id)
            let reordered = ChequeListEngine.reorderedIDs(all: global, visible: visible,
                                                         from: IndexSet(integer: 0), to: 2)
            let hidden = Set(global).subtracting(visible)
            for index in global.indices where hidden.contains(global[index]) {
                XCTAssertEqual(reordered[index], global[index])
            }
            XCTAssertEqual(reordered.filter { !hidden.contains($0) }, Array(visible.reversed()))
            let byID = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) })
            for (index, id) in reordered.enumerated() {
                byID[id]?.manualRank = ascending ? Int64(index) : Int64(reordered.count - index)
            }
            try context.save()

            let fresh = ModelContext(container)
            let loaded = try fresh.fetch(FetchDescriptor<ChequeRecord>())
            let persisted = ChequeListEngine.filteredAndSorted(
                cheques: loaded.map(\.snapshot), filter: .init(), sort: .manual, ascending: ascending
            ).map(\.id)
            XCTAssertEqual(persisted, reordered)
        }
    }

    private func day(_ iso: String) throws -> LocalDay { try XCTUnwrap(LocalDay(iso: iso)) }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self])
        let configuration = ModelConfiguration("ChequeRecordTests", schema: schema,
                                               isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
