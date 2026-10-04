import Foundation

/// The rows and exact direction totals for one list update. Incoming and outgoing
/// values describe cheque volume independently; they are never a cash balance.
public struct ChequeListResult: Sendable {
    public let cheques: [ChequeSnapshot]
    public let totals: ChequeDirectionTotals

    public init(cheques: [ChequeSnapshot], filter: ChequeFilter, sort: ChequeSort,
                ascending: Bool, today: LocalDay = .today) {
        let selected = ChequeListEngine.filteredAndSorted(cheques: cheques, filter: filter,
                                                          sort: sort, ascending: ascending, today: today)
        self.cheques = selected
        self.totals = ChequeDirectionTotals(cheques: selected)
    }
}

public struct ChequeDirectionTotals: Equatable, Sendable {
    public let incomingMinorUnits: Int64?
    public let outgoingMinorUnits: Int64?
    public let incomingCount: Int
    public let outgoingCount: Int
    public let currencyCodes: Set<String>

    public var hasCurrencyConflict: Bool { currencyCodes.count > 1 }
    public var hasAmountOverflow: Bool { incomingMinorUnits == nil || outgoingMinorUnits == nil }

    public init(cheques: [ChequeSnapshot]) {
        var incoming: Int64? = 0
        var outgoing: Int64? = 0
        var incomingCount = 0
        var outgoingCount = 0
        var currencies: Set<String> = []
        for cheque in cheques {
            currencies.insert(cheque.currencyCode.uppercased())
            switch cheque.direction {
            case .incoming:
                incomingCount += 1
                incoming = Self.add(cheque.amountMinorUnits, to: incoming)
            case .outgoing:
                outgoingCount += 1
                outgoing = Self.add(cheque.amountMinorUnits, to: outgoing)
            }
        }
        self.incomingMinorUnits = incoming
        self.outgoingMinorUnits = outgoing
        self.incomingCount = incomingCount
        self.outgoingCount = outgoingCount
        self.currencyCodes = currencies
    }

    private static func add(_ amount: Int64, to total: Int64?) -> Int64? {
        guard amount >= 0, let total else { return nil }
        let result = total.addingReportingOverflow(amount)
        return result.overflow ? nil : result.partialValue
    }
}
