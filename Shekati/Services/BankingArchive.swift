import Foundation
import SwiftData
import ShekatiCore

struct BankingArchive: Codable, Equatable, Sendable {
    struct Account: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var currency: String
        var opening: Int64
        var createdAt: Date
        @MainActor init(_ record: BankAccountRecord) {
            id = record.id; name = record.name; currency = record.currencyCode
            opening = record.openingMinor; createdAt = record.createdAt
        }
    }
    struct Book: Codable, Equatable, Sendable {
        var id: UUID
        var accountID: UUID
        var name: String
        @MainActor init(_ record: ChequeBookRecord) {
            id = record.id; accountID = record.accountID; name = record.name
        }
    }
    var accounts: [Account]
    var books: [Book]
    var events: [LedgerOperation]

    @MainActor init(accounts: [BankAccountRecord], books: [ChequeBookRecord], events: [LedgerEventRecord]) throws {
        self.accounts = try Self.deduplicated(accounts.map(Account.init), by: \.id)
        self.books = try Self.deduplicated(books.map(Book.init), by: \.id)
        let decoded = events.compactMap(\.operation)
        guard decoded.count == events.count else { throw ChequeTransferError.invalidRecords }
        self.events = try Self.deduplicated(decoded, by: \.id)
    }

    private static func deduplicated<T: Equatable>(_ values: [T], by key: KeyPath<T, UUID>) throws -> [T] {
        var seen: [UUID: T] = [:]
        var unique: [T] = []
        for value in values {
            let id = value[keyPath: key]
            if let previous = seen[id] {
                guard previous == value else { throw ChequeTransferError.invalidRecords }
            } else {
                seen[id] = value
                unique.append(value)
            }
        }
        return unique
    }

    func validate(records: [ChequeBackupEntry]) throws {
        guard accounts.count <= 20_000, books.count <= 100_000, events.count <= 500_000 else { throw ChequeTransferError.invalidRecords }
        let accountIndex = Dictionary(grouping: accounts, by: \.id)
        let bookIndex = Dictionary(grouping: books, by: \.id)
        let cheques = Dictionary(grouping: records, by: \.snapshot.id)
        guard accountIndex.count == accounts.count, bookIndex.count == books.count, Set(events.map(\.id)).count == events.count,
              accounts.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 4096 && Locale.commonISOCurrencyCodes.contains($0.currency)
                  && ChequeBackupPayload.isRepresentableTimestamp($0.createdAt) }),
              books.allSatisfy({ accountIndex[$0.accountID] != nil && !$0.name.isEmpty && $0.name.utf8.count <= 4096 }) else {
            throw ChequeTransferError.invalidRecords
        }
        for entry in records {
            if let id = entry.bankAccountID, accountIndex[id]?.first?.currency != entry.snapshot.currencyCode { throw ChequeTransferError.invalidRecords }
            if let id = entry.chequeBookID {
                guard let accountID = entry.bankAccountID, bookIndex[id]?.first?.accountID == accountID else { throw ChequeTransferError.invalidRecords }
            }
            if let raw = entry.ledgerBaselineStatusRaw, PaperState(rawValue: raw) == nil { throw ChequeTransferError.invalidRecords }
            if let id = entry.replacesChequeID, cheques[id] == nil { throw ChequeTransferError.invalidRecords }
        }
        for op in events {
            guard let accountID = op.accountID, accountIndex[accountID]?.first?.currency == op.currency,
                  op.party.utf8.count <= 100_000 else { throw ChequeTransferError.invalidRecords }
            if let chequeID = op.chequeID {
                guard let entry = cheques[chequeID]?.first, entry.bankAccountID == accountID,
                      entry.snapshot.currencyCode == op.currency, op.kind != .reconcile else { throw ChequeTransferError.invalidRecords }
                if op.kind == .replace {
                    guard let child = op.relatedID, cheques[child]?.first?.replacesChequeID == chequeID else { throw ChequeTransferError.invalidRecords }
                }
            } else if op.kind != .reconcile && op.kind != .discardConflict { throw ChequeTransferError.invalidRecords }
        }
    }

    @MainActor func merge(into context: ModelContext) throws {
        let oldAccounts = Dictionary(grouping: try context.fetch(FetchDescriptor<BankAccountRecord>()), by: \.id)
        let oldBooks = Dictionary(grouping: try context.fetch(FetchDescriptor<ChequeBookRecord>()), by: \.id)
        let oldEvents = Dictionary(grouping: try context.fetch(FetchDescriptor<LedgerEventRecord>()), by: \.id)
        for account in accounts {
            if let existing = oldAccounts[account.id] {
                guard existing.allSatisfy({ $0.currencyCode == account.currency && $0.openingMinor == account.opening }) else { throw ChequeTransferError.invalidRecords }
            } else {
                context.insert(BankAccountRecord(id: account.id, name: account.name, currencyCode: account.currency, openingMinor: account.opening, createdAt: account.createdAt))
            }
        }
        for book in books {
            if let existing = oldBooks[book.id] {
                guard existing.allSatisfy({ $0.accountID == book.accountID }) else { throw ChequeTransferError.invalidRecords }
            } else { context.insert(ChequeBookRecord(id: book.id, accountID: book.accountID, name: book.name)) }
        }
        for op in events {
            if let existing = oldEvents[op.id] {
                guard existing.allSatisfy({ $0.operation == op }) else { throw ChequeTransferError.invalidRecords }
            } else { context.insert(LedgerEventRecord(op)) }
        }
    }
}
