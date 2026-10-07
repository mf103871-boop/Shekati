import Foundation

/// An exact total for the selected records in the supplied list. Pass the visible records
/// when a filter is active so hidden or removed records cannot remain in the total.
public struct ChequeSelectionSummary: Equatable, Sendable {
    public let selectedIDs: Set<UUID>
    public var count: Int { selectedIDs.count }
    public let currencyCode: String?
    public let hasCurrencyConflict: Bool
    public let hasOverflow: Bool
    public let hasInvalidValues: Bool
    /// Zero for an empty selection; nil for mixed currencies, invalid values, or overflow.
    public let totalMinorUnits: Int64?

    public init(cheques: [ChequeSnapshot], selectedIDs: Set<UUID>) {
        var includedIDs = Set<UUID>()
        var currencies = Set<String>()
        var total: Int64 = 0
        var overflow = false
        var invalid = false

        for cheque in cheques where selectedIDs.contains(cheque.id) {
            // A repeated snapshot must not count the same cheque twice. The first wins.
            guard includedIDs.insert(cheque.id).inserted else { continue }
            let currency = cheque.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if currency.isEmpty { invalid = true } else { currencies.insert(currency) }
            guard cheque.amountMinorUnits > 0 else {
                invalid = true
                continue
            }
            if !overflow {
                let result = total.addingReportingOverflow(cheque.amountMinorUnits)
                overflow = result.overflow
                total = result.partialValue
            }
        }

        self.selectedIDs = includedIDs
        currencyCode = currencies.count == 1 ? currencies.first : nil
        hasCurrencyConflict = currencies.count > 1
        hasOverflow = overflow
        hasInvalidValues = invalid
        totalMinorUnits = overflow || invalid || hasCurrencyConflict ? nil : total
    }
}
