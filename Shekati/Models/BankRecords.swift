import Foundation
import SwiftData
import ShekatiCore

@Model
final class BankAccountRecord {
    var id: UUID = UUID()
    var name: String = ""
    var currencyCode: String = ""
    var openingMinor: Int64 = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, currencyCode: String, openingMinor: Int64, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.openingMinor = openingMinor
        self.createdAt = createdAt
    }
}

@Model
final class ChequeBookRecord {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var name: String = ""

    init(id: UUID = UUID(), accountID: UUID, name: String) {
        self.id = id
        self.accountID = accountID
        self.name = name
    }
}

@Model
final class LedgerEventRecord {
    var id: UUID = UUID()
    var parentID: UUID?
    var chequeID: UUID?
    var accountID: UUID?
    var kindRaw: String = ""
    var dayISO: String = ""
    var amountMinor: Int64 = 0
    var party: String = ""
    var relatedID: UUID?
    var currencyCode: String = ""

    init(_ op: LedgerOperation) {
        id = op.id; parentID = op.parentID; chequeID = op.chequeID; accountID = op.accountID
        kindRaw = op.kind.rawValue; dayISO = op.day.iso; amountMinor = op.amount
        party = op.party; relatedID = op.relatedID; currencyCode = op.currency
    }

    var operation: LedgerOperation? {
        guard let kind = LedgerAction(rawValue: kindRaw), let day = LocalDay(iso: dayISO) else { return nil }
        return LedgerOperation(id: id, parentID: parentID, chequeID: chequeID, accountID: accountID,
                               kind: kind, day: day, amount: amountMinor, party: party,
                               relatedID: relatedID, currency: currencyCode)
    }
}
