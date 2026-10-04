import Foundation
import ShekatiCore

/// Suggestions and soft duplicate detection never change the values the user entered.
enum ChequeEntryAssistance {
    static func normalized(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.map { character in
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return character }
            return Character(String(digit))
        })
    }

    static func suggestions(from values: [String], matching query: String, limit: Int = 5) -> [String] {
        let search = normalized(query)
        var seen: Set<String> = []
        return values.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(trimmed)
            guard !key.isEmpty, key != search, search.isEmpty || key.contains(search), seen.insert(key).inserted else { return nil }
            return trimmed
        }.prefix(max(0, limit)).map { $0 }
    }

    /// Compare active snapshots only. This is a warning, never a uniqueness constraint.
    static func probableDuplicateIDs(for draft: ChequeSnapshot, among existing: [ChequeSnapshot],
                                     excluding id: UUID? = nil) -> [UUID] {
        existing.filter { other in
            guard other.id != id, other.direction == draft.direction,
                  other.currencyCode == draft.currencyCode else { return false }
            let bank = normalized(draft.bank), otherBank = normalized(other.bank)
            let account = normalized(draft.accountReference), otherAccount = normalized(other.accountReference)
            if !bank.isEmpty && !otherBank.isEmpty && bank != otherBank { return false }
            if !account.isEmpty && !otherAccount.isEmpty && account != otherAccount { return false }
            let number = normalized(draft.number), otherNumber = normalized(other.number)
            let sameAmountAndDate = draft.amountMinorUnits == other.amountMinorUnits && draft.dueDate == other.dueDate
            if !number.isEmpty || !otherNumber.isEmpty {
                guard !number.isEmpty, number == otherNumber else { return false }
                return (!bank.isEmpty && bank == otherBank) ||
                    (!account.isEmpty && account == otherAccount) || sameAmountAndDate
            }
            let party = normalized(draft.party)
            return sameAmountAndDate && !party.isEmpty && party == normalized(other.party)
        }.map(\.id)
    }
}
