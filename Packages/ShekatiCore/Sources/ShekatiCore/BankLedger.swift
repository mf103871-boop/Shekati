import Foundation

public enum PaperState: String, Codable, Sendable, CaseIterable {
    case draft, issued, inHand, deposited, endorsed, returned, legal, lost, settled, cancelled, replaced
    public var title: String {
        switch self {
        case .draft: return "Draft"
        case .issued: return "Issued"
        case .inHand: return "In hand"
        case .deposited: return "Deposited"
        case .endorsed: return "Endorsed"
        case .returned: return "Returned"
        case .legal: return "Legal follow-up"
        case .lost: return "Lost"
        case .settled: return "Settled"
        case .cancelled: return "Cancelled"
        case .replaced: return "Replaced"
        }
    }
    public static func initial(_ status: ChequeStatus, direction: ChequeDirection) -> Self {
        switch status {
        case .settled: return .settled
        case .returned: return .returned
        case .cancelled: return .cancelled
        case .pending: return direction == .incoming ? .inHand : .issued
        }
    }
}

public enum LedgerAction: String, Codable, CaseIterable, Sendable {
    case issue, deposit, settle, partialBank, partialCash, endorse, acknowledgeEndorsement
    case markReturned, markLost, legal, cancel, replace, reconcile, discardConflict
    public var title: String {
        switch self {
        case .issue: return "Issue cheque"
        case .deposit: return "Record deposit"
        case .settle: return "Record bank settlement"
        case .partialBank: return "Partial bank transfer"
        case .partialCash: return "Partial cash payment"
        case .endorse: return "Endorse cheque"
        case .acknowledgeEndorsement: return "Confirm holder collected"
        case .markReturned: return "Record return"
        case .markLost: return "Report lost cheque"
        case .legal: return "Start legal follow-up"
        case .cancel: return "Cancel cheque"
        case .replace: return "Replace cheque"
        case .reconcile: return "Reconcile account"
        case .discardConflict: return "Dismiss conflicting entry"
        }
    }
    public var isPremium: Bool {
        [.partialBank, .partialCash, .endorse, .legal, .replace].contains(self)
    }
}

/// An immutable operation. parentID is the last accepted operation the device actually saw.
/// Bank adjustments use chequeID == nil; a deposit or endorsement never moves bank money.
public struct LedgerOperation: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let parentID: UUID?
    public let chequeID: UUID?
    public let accountID: UUID?
    public let kind: LedgerAction
    public let day: LocalDay
    public let amount: Int64
    public let party: String
    public let relatedID: UUID?
    public let currency: String

    public init(id: UUID = UUID(), parentID: UUID? = nil, chequeID: UUID?, accountID: UUID?,
                kind: LedgerAction, day: LocalDay, amount: Int64 = 0, party: String = "",
                relatedID: UUID? = nil, currency: String) {
        self.id = id
        self.parentID = parentID
        self.chequeID = chequeID
        self.accountID = accountID
        self.kind = kind
        self.day = day
        self.amount = amount
        self.party = party
        self.relatedID = relatedID
        self.currency = currency
    }
}

public struct ChequePosition: Sendable {
    public let original: Int64
    public let direction: ChequeDirection
    public private(set) var state: PaperState
    public private(set) var paid: Int64
    public private(set) var holder: String = ""
    public private(set) var replacementID: UUID?
    public private(set) var accepted: [LedgerOperation] = []
    public private(set) var conflicts: [LedgerOperation] = []
    public private(set) var bankMovements: [UUID: Int64] = [:] // operation ID -> signed change

    public var remaining: Int64 { original - paid }
    public var isOpen: Bool { ![.settled, .cancelled, .replaced].contains(state) }
    public var legacyStatus: ChequeStatus {
        switch state {
        case .settled: return .settled
        case .returned, .legal: return .returned
        case .cancelled, .replaced: return .cancelled
        default: return .pending
        }
    }
    public var allowed: [LedgerAction] {
        switch state {
        case .draft: return [.issue, .cancel]
        case .inHand: return [.deposit, .settle, .endorse, .partialBank, .partialCash, .markReturned, .replace, .cancel]
        case .issued: return [.settle, .partialBank, .partialCash, .markReturned, .markLost, .replace, .cancel]
        case .deposited: return [.settle, .markReturned]
        case .endorsed: return [.acknowledgeEndorsement, .markReturned]
        case .returned: return [.settle, .partialBank, .partialCash, .replace, .cancel] + (direction == .incoming ? [.deposit, .legal] : [])
        case .legal: return [.settle, .partialBank, .partialCash, .replace, .cancel]
        case .lost: return [.replace, .cancel, .settle]
        default: return []
        }
    }

    public init(original: Int64, direction: ChequeDirection, baseline: PaperState,
                currency: String, operations: [LedgerOperation]) {
        self.original = max(original, 0)
        self.direction = direction
        state = baseline
        paid = baseline == .settled ? self.original : 0

        let sets = Dictionary(grouping: operations, by: \.id)
        let duplicates = sets.values.filter { group in
            guard let first = group.first else { return false }
            return group.contains { $0 != first }
        }.flatMap { $0 }
        guard duplicates.isEmpty else {
            conflicts = duplicates
            return
        }
        let unique = sets.values.compactMap(\.first)
        let dismissed = Set(unique.filter { $0.kind == .discardConflict }.compactMap(\.relatedID))
        let movements = unique.filter { $0.kind != .discardConflict }
        let children = Dictionary(grouping: movements, by: \.parentID)
        // Dismissing a stale branch also discards its causal descendants.
        var discarded = dismissed
        var stack = Array(dismissed)
        while let parent = stack.popLast() {
            for child in children[parent] ?? [] where discarded.insert(child.id).inserted {
                stack.append(child.id)
            }
        }
        var seen = Set<UUID>()
        var parent: UUID?
        while true {
            let next = (children[parent] ?? []).filter { !discarded.contains($0.id) }
            guard next.count == 1, let operation = next.first, seen.insert(operation.id).inserted,
                  operation.currency == currency, apply(operation) else { break }
            accepted.append(operation)
            parent = operation.id
        }
        let acceptedIDs = Set(accepted.map(\.id))
        conflicts = movements.filter { !acceptedIDs.contains($0.id) && !discarded.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private mutating func apply(_ op: LedgerOperation) -> Bool {
        guard allowed.contains(op.kind), accepted.last.map({ op.day >= $0.day }) ?? true else { return false }
        switch op.kind {
        case .settle, .partialBank, .partialCash, .acknowledgeEndorsement:
            guard op.amount > 0, op.amount <= remaining else { return false }
            if op.kind == .settle || op.kind == .acknowledgeEndorsement {
                guard op.amount == remaining else { return false }
            }
            if op.kind == .settle || op.kind == .partialBank {
                guard op.accountID != nil else { return false }
                bankMovements[op.id] = direction == .incoming ? op.amount : -op.amount
            }
            paid += op.amount
            if remaining == 0 { state = .settled }
        case .replace:
            guard op.relatedID != nil, op.amount == remaining else { return false }
            replacementID = op.relatedID
            state = .replaced
        case .endorse:
            guard !op.party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            holder = op.party
            state = .endorsed
        case .issue: state = .issued
        case .deposit: state = .deposited
        case .markReturned: state = .returned; holder = ""
        case .markLost: state = .lost
        case .legal: state = .legal
        case .cancel: state = .cancelled
        default: return false
        }
        return true
    }
}

public struct TreasuryItem: Sendable {
    public let id: UUID
    public let due: LocalDay
    public let direction: ChequeDirection
    public let state: PaperState
    public let remaining: Int64
    public init(id: UUID, due: LocalDay, direction: ChequeDirection, state: PaperState, remaining: Int64) {
        self.id = id; self.due = due; self.direction = direction; self.state = state; self.remaining = remaining
    }
}

public struct CashPoint: Identifiable, Sendable {
    public var id: LocalDay { day }
    public let day: LocalDay
    public let balance: Int64
    public let contributors: [UUID]
}

public enum TreasuryError: Error { case overflow }

public struct AccountOutlook: Sendable {
    public let recorded: Int64
    public let outgoing7: Int64
    public let incoming7: Int64
    public let available7: Int64
    public let points: [CashPoint]

    public init(opening: Int64, movements: [Int64], items: [TreasuryItem], today: LocalDay, horizon: Int = 60) throws {
        recorded = try Self.sum(opening, movements)
        let eligible = items.filter { item in
            guard item.remaining > 0 else { return false }
            if item.direction == .incoming { return [.inHand, .deposited].contains(item.state) && item.due >= today }
            return [.issued, .returned, .lost].contains(item.state)
        }
        let weekly = eligible.filter { $0.due <= today.adding(days: 7) }
        outgoing7 = try Self.sum(0, weekly.filter { $0.direction == .outgoing }.map(\.remaining))
        incoming7 = try Self.sum(0, weekly.filter { $0.direction == .incoming }.map(\.remaining))
        available7 = try Self.sum(recorded, [-outgoing7])
        let cutoff = today.adding(days: min(max(horizon, 0), 366))
        let byDay = Dictionary(grouping: eligible.filter { $0.due <= cutoff }, by: { max(today, $0.due) })
        var balance = recorded
        var output: [CashPoint] = []
        for day in Set(byDay.keys).union([today, cutoff]).sorted() {
            let due = byDay[day] ?? []
            balance = try Self.sum(balance, due.map { $0.direction == .incoming ? $0.remaining : -$0.remaining })
            output.append(CashPoint(day: day, balance: balance, contributors: due.map(\.id)))
        }
        points = output
    }

    public static func sum(_ initial: Int64, _ values: [Int64]) throws -> Int64 {
        // Decimal can sum the full range of an Int64 ledger without order-dependent intermediate overflow.
        let total = values.reduce(Decimal(initial)) { $0 + Decimal($1) }
        guard total >= Decimal(Int64.min), total <= Decimal(Int64.max) else { throw TreasuryError.overflow }
        return NSDecimalNumber(decimal: total).int64Value
    }
}
