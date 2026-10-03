import Foundation

public enum ChequeListEngine {
    public static func filteredAndSorted(cheques: [ChequeSnapshot], filter: ChequeFilter,
                                         sort: ChequeSort, ascending: Bool, today: LocalDay = .today) -> [ChequeSnapshot] {
        let query = searchable(filter.query.trimmingCharacters(in: .whitespacesAndNewlines))
        let weekEnd = today.adding(days: 7)
        return cheques.filter { cheque in
            if filter.outstandingOnly && !cheque.isOutstanding { return false }
            if let direction = filter.direction, cheque.direction != direction { return false }
            if let status = filter.status, cheque.status != status { return false }
            if let bank = filter.bank, searchable(cheque.bank) != searchable(bank) { return false }
            if let from = filter.from, cheque.dueDate < from { return false }
            if let through = filter.through, cheque.dueDate > through { return false }
            if !query.isEmpty && ![cheque.number, cheque.party, cheque.bank].contains(where: { searchable($0).contains(query) }) { return false }
            switch filter.dateScope {
            case .all: break
            case .today: if !cheque.isOutstanding || cheque.dueDate != today { return false }
            case .upcoming: if !cheque.isOutstanding || cheque.dueDate <= today || cheque.dueDate > weekEnd { return false }
            case .overdue: if !cheque.isOverdue(on: today) { return false }
            }
            return true
        }.sorted { lhs, rhs in
            let order: ComparisonResult
            switch sort {
            case .dueDate: order = compare(lhs.dueDate, rhs.dueDate)
            case .amount: order = compare(lhs.amountMinorUnits, rhs.amountMinorUnits)
            case .name: order = compare(searchable(lhs.party), searchable(rhs.party))
            case .status: order = compare(statusRank(lhs.status), statusRank(rhs.status))
            case .createdAt: order = compare(lhs.createdAt, rhs.createdAt)
            case .manual: order = compare(lhs.manualRank, rhs.manualRank)
            }
            if order != .orderedSame { return ascending ? order == .orderedAscending : order == .orderedDescending }
            // Tie breakers stay fixed when the primary order is reversed.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Matches List.onMove semantics, replacing only the global slots occupied by visible IDs.
    public static func reorderedIDs(all: [UUID], visible: [UUID], from: IndexSet, to: Int) -> [UUID] {
        guard Set(all).count == all.count, Set(visible).count == visible.count,
              Set(visible).isSubset(of: Set(all)), (0...visible.count).contains(to),
              from.allSatisfy({ visible.indices.contains($0) }) else { return all }
        let moved = from.sorted().map { visible[$0] }
        var remaining = visible.enumerated().filter { !from.contains($0.offset) }.map(\.element)
        let insertion = to - from.filter { $0 < to }.count
        remaining.insert(contentsOf: moved, at: insertion)
        let visibleSet = Set(visible)
        var replacementIndex = 0
        return all.map { id in
            guard visibleSet.contains(id) else { return id }
            defer { replacementIndex += 1 }
            return remaining[replacementIndex]
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (rhs < lhs ? .orderedDescending : .orderedSame)
    }

    private static func statusRank(_ status: ChequeStatus) -> Int {
        switch status { case .pending: return 0; case .returned: return 1; case .settled: return 2; case .cancelled: return 3 }
    }

    private static func searchable(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.map { character in
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return character }
            return Character(String(digit))
        })
    }
}

public struct DashboardMetrics: Equatable, Sendable {
    public let incomingMinorUnits: Int64
    public let outgoingMinorUnits: Int64
    public let todayCount: Int
    public let upcomingCount: Int
    public let overdueCount: Int
    public let hasAmountOverflow: Bool

    public init(cheques: [ChequeSnapshot], today: LocalDay = .today) {
        let outstanding = cheques.filter(\.isOutstanding)
        func total(_ direction: ChequeDirection) -> (value: Int64, overflow: Bool) {
            var sum: Int64 = 0
            for cheque in outstanding where cheque.direction == direction {
                let result = sum.addingReportingOverflow(max(0, cheque.amountMinorUnits))
                if result.overflow { return (Int64.max, true) }
                sum = result.partialValue
            }
            return (sum, false)
        }
        let incoming = total(.incoming)
        let outgoing = total(.outgoing)
        incomingMinorUnits = incoming.value
        outgoingMinorUnits = outgoing.value
        hasAmountOverflow = incoming.overflow || outgoing.overflow ||
            incoming.value.addingReportingOverflow(outgoing.value).overflow
        todayCount = outstanding.filter { $0.dueDate == today }.count
        let weekEnd = today.adding(days: 7)
        upcomingCount = outstanding.filter { $0.dueDate > today && $0.dueDate <= weekEnd }.count
        overdueCount = outstanding.filter { $0.isOverdue(on: today) }.count
    }
}
