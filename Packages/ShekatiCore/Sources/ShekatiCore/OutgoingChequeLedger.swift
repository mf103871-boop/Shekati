import Foundation

/// The outgoing cheques sheet: every outgoing cheque in cheque-date order, the outstanding amount
/// still to be paid from each row onward, and each amount's bar length relative to the largest.
public struct OutgoingChequeLedger: Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let cheque: ChequeSnapshot
        /// Pending and returned amounts on this row and every later row. Paid and cancelled
        /// cheques stay listed but are not owed. `nil` when the sum exceeds the supported range.
        public let remainingMinorUnits: Int64?
        /// The amount relative to the largest amount listed, from 0 through 1.
        public let barFraction: Double
        public var id: UUID { cheque.id }
    }

    public let rows: [Row]
    public let currencyCodes: Set<String>
    /// Balances mix currencies and must not be shown when the listed cheques use more than one.
    public var hasCurrencyConflict: Bool { currencyCodes.count > 1 }

    public init(cheques: [ChequeSnapshot]) {
        let outgoing = cheques.filter { $0.direction == .outgoing }.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var remaining = [Int64?](repeating: nil, count: outgoing.count)
        var running: Int64? = 0
        for index in outgoing.indices.reversed() {
            let cheque = outgoing[index]
            if cheque.isOutstanding, let total = running {
                let next = total.addingReportingOverflow(max(0, cheque.amountMinorUnits))
                running = next.overflow ? nil : next.partialValue
            }
            remaining[index] = running
        }
        let largest = outgoing.map { max(0, $0.amountMinorUnits) }.max() ?? 0
        rows = outgoing.indices.map { index in
            let amount = max(0, outgoing[index].amountMinorUnits)
            return Row(cheque: outgoing[index], remainingMinorUnits: remaining[index],
                       barFraction: largest > 0 ? Double(amount) / Double(largest) : 0)
        }
        currencyCodes = Set(outgoing.map { $0.currencyCode.uppercased() })
    }

    /// Day/month/year with Western digits, as written on the cheque sheet: `04/10/2026`.
    public static func dateText(_ day: LocalDay) -> String {
        let parts = day.iso.split(separator: "-")
        return "\(parts[2])/\(parts[1])/\(parts[0])"
    }
}
