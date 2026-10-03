import Foundation
import XCTest
@testable import ShekatiCore

final class ChequeListEngineTests: XCTestCase {
    private let today = LocalDay(iso: "2026-10-03")!

    private func cheque(_ offset: Int = 0, status: ChequeStatus = .pending,
                        direction: ChequeDirection = .incoming, amount: Int64 = 1000,
                        number: String = "000123", bank: String = "Bank A", party: String = "Ali", rank: Int64 = 0) -> ChequeSnapshot {
        ChequeSnapshot(direction: direction, status: status, amountMinorUnits: amount, currencyCode: "JOD",
                       dueDate: today.adding(days: offset), number: number, bank: bank, party: party,
                       createdAt: Date(timeIntervalSince1970: 1), manualRank: rank)
    }

    func testStatusMeaningAndDateNeverSettlesAutomatically() {
        XCTAssertTrue(cheque(-1).isOverdue(on: today))
        XCTAssertTrue(cheque(-1, status: .returned).isOverdue(on: today))
        XCTAssertFalse(cheque(-1, status: .settled).isOverdue(on: today))
        XCTAssertFalse(cheque(-1, status: .cancelled).isOutstanding)
        XCTAssertFalse(cheque().isOverdue(on: today))
        XCTAssertEqual(cheque(-20).status, .pending)
    }

    func testDashboardDirectionDrilldownMatchesOutstandingTotals() {
        let records = [cheque(amount: 100), cheque(status: .returned, amount: 200), cheque(status: .settled, amount: 300), cheque(status: .cancelled, amount: 400), cheque(direction: .outgoing, amount: 500)]
        let result = ChequeListEngine.filteredAndSorted(cheques: records, filter: ChequeFilter(direction: .incoming, outstandingOnly: true), sort: .dueDate, ascending: true, today: today)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amountMinorUnits).reduce(0, +), DashboardMetrics(cheques: records, today: today).incomingMinorUnits)
    }

    func testChequeNumberLeadingZerosAndFullSnapshotRoundTrip() throws {
        var original = cheque(number: "00000123")
        original.actualDate = today
        original.issueDate = today.adding(days: -30)
        original.branch = "Main"
        original.accountReference = "001122"
        original.notes = "Cheque notes"
        let decoded = try JSONDecoder().decode(ChequeSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.number, "00000123")
    }

    func testSearchFoldsCaseAccentsAndArabicDigits() {
        let records = [cheque(number: "000123", party: "ÉLIAS"), cheque(number: "00999", bank: "Other", party: "Omar")]
        for query in ["elias", "٠٠٠١٢٣", "BANK A"] {
            let result = ChequeListEngine.filteredAndSorted(cheques: records, filter: ChequeFilter(query: query), sort: .dueDate, ascending: true, today: today)
            XCTAssertEqual(result.count, 1, query)
            XCTAssertEqual(result.first?.id, records[0].id)
        }
    }

    func testCombinedFilterUsesInclusiveDateBounds() {
        let records = [cheque(1), cheque(2, direction: .outgoing), cheque(3, status: .returned), cheque(4, bank: "Other"), cheque(5)]
        let filter = ChequeFilter(direction: .incoming, status: .pending, bank: "bank a", from: today.adding(days: 1), through: today.adding(days: 4))
        let result = ChequeListEngine.filteredAndSorted(cheques: records, filter: filter, sort: .dueDate, ascending: true, today: today)
        XCTAssertEqual(result.map(\.id), [records[0].id])
    }

    func testDateScopesAndDashboardUseOnlyOutstandingCheques() {
        let records = [cheque(-1), cheque(), cheque(1), cheque(7, status: .returned), cheque(8), cheque(-1, status: .settled), cheque(status: .cancelled)]
        for (scope, count) in [(ChequeDateScope.today, 1), (.upcoming, 2), (.overdue, 1), (.all, 7)] {
            XCTAssertEqual(ChequeListEngine.filteredAndSorted(cheques: records, filter: ChequeFilter(dateScope: scope), sort: .dueDate, ascending: true, today: today).count, count)
        }
        let metrics = DashboardMetrics(cheques: records + [cheque(direction: .outgoing, amount: 500)], today: today)
        XCTAssertEqual(metrics.incomingMinorUnits, 5000)
        XCTAssertEqual(metrics.outgoingMinorUnits, 500)
        XCTAssertEqual(metrics.todayCount, 2)
        XCTAssertEqual(metrics.upcomingCount, 2)
        XCTAssertEqual(metrics.overdueCount, 1)
    }

    func testSortsInBothDirectionsWithDeterministicTies() {
        let small = cheque(1, amount: 100, party: "Zed", rank: 2)
        let large = cheque(2, amount: 200, party: "Ali", rank: 1)
        let records = [large, small]
        XCTAssertEqual(sorted(records, .amount, true).first?.id, small.id)
        XCTAssertEqual(sorted(records, .amount, false).first?.id, large.id)
        XCTAssertEqual(sorted(records, .name, true).first?.id, large.id)
        XCTAssertEqual(sorted(records, .dueDate, false).first?.id, large.id)
        XCTAssertEqual(sorted(records, .manual, true).first?.id, large.id)
        let ties = [cheque(), cheque(), cheque()]
        XCTAssertEqual(sorted(ties, .amount, true).map(\.id), sorted(Array(ties.reversed()), .amount, false).map(\.id))
    }

    func testReorderKeepsHiddenSlotsAndSupportsMultipleMoves() {
        let ids = (0..<6).map { _ in UUID() }
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: [ids[0], ids[2], ids[4]], from: IndexSet(integer: 0), to: 3), [ids[2], ids[1], ids[4], ids[3], ids[0], ids[5]])
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: ids, from: IndexSet([1, 3]), to: 6), [ids[0], ids[2], ids[4], ids[5], ids[1], ids[3]])
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: ids, from: IndexSet(integer: 4), to: 1), [ids[0], ids[4], ids[1], ids[2], ids[3], ids[5]])
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: ids, from: IndexSet(integer: 1), to: 2), ids)
    }

    func testInvalidReorderInputsLeaveOrderIntact() {
        let ids = (0..<3).map { _ in UUID() }
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: [UUID()], from: IndexSet(integer: 0), to: 1), ids)
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: ids, from: IndexSet(integer: 9), to: 0), ids)
        XCTAssertEqual(ChequeListEngine.reorderedIDs(all: ids, visible: ids, from: IndexSet(integer: 0), to: 4), ids)
    }

    func testThousandRecordsFilterSortAndReorder() {
        let records = (0..<1000).map { index in
            cheque(index % 31 - 15, direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                   amount: Int64(index + 1), number: String(format: "%06d", index), rank: Int64(index))
        }
        let result = ChequeListEngine.filteredAndSorted(cheques: records, filter: ChequeFilter(direction: .incoming), sort: .amount, ascending: false, today: today)
        XCTAssertEqual(result.count, 500)
        XCTAssertEqual(result.first?.amountMinorUnits, 999)
        let all = records.map(\.id)
        let visible = records.filter { $0.direction == .incoming }.map(\.id)
        let reordered = ChequeListEngine.reorderedIDs(all: all, visible: visible, from: IndexSet(integer: 0), to: visible.count)
        for index in stride(from: 1, to: 1000, by: 2) { XCTAssertEqual(reordered[index], all[index]) }
        XCTAssertEqual(Set(reordered), Set(all))
    }

    func testDashboardDoesNotTrapOnCorruptOrExtremeAmounts() {
        let metrics = DashboardMetrics(cheques: [cheque(amount: .max), cheque(amount: 1), cheque(amount: -100)], today: today)
        XCTAssertEqual(metrics.incomingMinorUnits, .max)
    }

    private func sorted(_ values: [ChequeSnapshot], _ sort: ChequeSort, _ ascending: Bool) -> [ChequeSnapshot] {
        ChequeListEngine.filteredAndSorted(cheques: values, filter: ChequeFilter(), sort: sort, ascending: ascending, today: today)
    }
}
