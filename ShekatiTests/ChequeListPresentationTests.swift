import Foundation
import SwiftData
import XCTest
import ShekatiCore
@testable import Shekati

@MainActor
final class ChequeListPresentationTests: XCTestCase {
    func testHistoryScopeDefaultsToOutstandingAndPersistsWithSortAcrossRestart() throws {
        let suite = "Shekati.ListPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = UserPreferences(defaults: defaults)
        XCTAssertEqual(initial.chequeListScope, .outstanding)
        initial.chequeListScope = .allRecords
        initial.sort = .manual
        initial.ascending = false
        let reopened = UserPreferences(defaults: defaults)
        XCTAssertEqual(reopened.chequeListScope, .allRecords)
        XCTAssertEqual(reopened.sort, .manual)
        XCTAssertFalse(reopened.ascending)
        reopened.chequeListScope = .outstanding
        XCTAssertEqual(UserPreferences(defaults: defaults).chequeListScope, .outstanding)
    }

    func testSoftDeletedRecordStaysOutOfQueryTotalsAndKeepsHiddenManualSlotUntilRestored() throws {
        for ascending in [true, false] {
            let schema = Schema([ChequeRecord.self, AppConfiguration.self])
            let configuration = ModelConfiguration("ListPresentationTests", schema: schema,
                                                    isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let records = (0..<6).map { index in
                ChequeRecord(snapshot: ChequeSnapshot(
                    direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                    amountMinorUnits: Int64(index + 1) * 1_001, currencyCode: "JOD",
                    dueDate: LocalDay(iso: "2026-10-04")!, number: String(format: "%04d", index),
                    manualRank: Int64(index)
                ))
            }
            records.forEach { context.insert($0) }
            records[2].deletedAt = Date()
            try context.save()
            let active = try context.fetch(FetchDescriptor<ChequeRecord>(predicate: #Predicate { $0.deletedAt == nil }))
            XCTAssertEqual(active.count, 5)
            let selected = ChequeListResult(cheques: active.map(\.snapshot),
                                           filter: .init(direction: .incoming, outstandingOnly: true),
                                           sort: .manual, ascending: ascending)
            XCTAssertEqual(selected.cheques.count, 2)
            XCTAssertEqual(selected.totals.incomingMinorUnits, 6_006)
            XCTAssertFalse(selected.cheques.contains { $0.id == records[2].id })
            let global = ChequeListEngine.filteredAndSorted(cheques: records.map(\.snapshot),
                                                            filter: .init(), sort: .manual, ascending: ascending).map(\.id)
            let reordered = ChequeListEngine.reorderedIDs(all: global, visible: selected.cheques.map(\.id),
                                                         from: IndexSet(integer: 0), to: 2)
            let deletedSlot = try XCTUnwrap(global.firstIndex(of: records[2].id))
            XCTAssertEqual(reordered[deletedSlot], records[2].id)
            let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            for (index, id) in reordered.enumerated() {
                byID[id]?.manualRank = ascending ? Int64(index) : Int64(reordered.count - index)
            }
            try context.save()
            let liveOrder = ChequeListEngine.filteredAndSorted(cheques: active.map(\.snapshot),
                                                               filter: .init(), sort: .manual, ascending: ascending).map(\.id)
            records[2].deletedAt = nil
            try context.save()
            let restored = try context.fetch(FetchDescriptor<ChequeRecord>(predicate: #Predicate { $0.deletedAt == nil }))
            let restoredOrder = ChequeListEngine.filteredAndSorted(cheques: restored.map(\.snapshot),
                                                                   filter: .init(), sort: .manual, ascending: ascending).map(\.id)
            XCTAssertEqual(restoredOrder[deletedSlot], records[2].id)
            XCTAssertEqual(restoredOrder.filter { $0 != records[2].id }, liveOrder)
        }
    }
}
