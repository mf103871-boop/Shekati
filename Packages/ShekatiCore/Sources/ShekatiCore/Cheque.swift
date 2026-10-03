import Foundation

public enum ChequeDirection: String, Codable, CaseIterable, Hashable, Sendable { case incoming, outgoing }
public enum ChequeStatus: String, Codable, CaseIterable, Hashable, Sendable { case pending, settled, returned, cancelled }
public enum ChequeSort: String, Codable, CaseIterable, Hashable, Sendable { case dueDate, amount, name, status, createdAt, manual }
public enum ChequeDateScope: String, Codable, CaseIterable, Hashable, Sendable { case all, today, upcoming, overdue }

public struct ChequeSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var direction: ChequeDirection
    public var status: ChequeStatus
    public var amountMinorUnits: Int64
    public var currencyCode: String
    public var dueDate: LocalDay
    public var actualDate: LocalDay?
    public var issueDate: LocalDay?
    public var number: String
    public var bank: String
    public var branch: String
    public var party: String
    public var accountReference: String
    public var notes: String
    public var createdAt: Date
    public var manualRank: Int64

    public init(id: UUID = UUID(), direction: ChequeDirection, status: ChequeStatus = .pending,
                amountMinorUnits: Int64, currencyCode: String, dueDate: LocalDay,
                actualDate: LocalDay? = nil, issueDate: LocalDay? = nil,
                number: String = "", bank: String = "", branch: String = "", party: String = "",
                accountReference: String = "", notes: String = "", createdAt: Date = Date(), manualRank: Int64 = 0) {
        self.id = id
        self.direction = direction
        self.status = status
        self.amountMinorUnits = amountMinorUnits
        self.currencyCode = currencyCode
        self.dueDate = dueDate
        self.actualDate = actualDate
        self.issueDate = issueDate
        self.number = number
        self.bank = bank
        self.branch = branch
        self.party = party
        self.accountReference = accountReference
        self.notes = notes
        self.createdAt = createdAt
        self.manualRank = manualRank
    }

    public var isOutstanding: Bool { status == .pending || status == .returned }
    public func isOverdue(on day: LocalDay) -> Bool { isOutstanding && dueDate < day }
}

public struct ChequeFilter: Equatable, Sendable {
    public var query: String
    public var direction: ChequeDirection?
    public var status: ChequeStatus?
    public var bank: String?
    public var from: LocalDay?
    public var through: LocalDay?
    public var dateScope: ChequeDateScope
    public var outstandingOnly: Bool

    public init(query: String = "", direction: ChequeDirection? = nil, status: ChequeStatus? = nil,
                bank: String? = nil, from: LocalDay? = nil, through: LocalDay? = nil,
                dateScope: ChequeDateScope = .all, outstandingOnly: Bool = false) {
        self.query = query
        self.direction = direction
        self.status = status
        self.bank = bank
        self.from = from
        self.through = through
        self.dateScope = dateScope
        self.outstandingOnly = outstandingOnly
    }
}
