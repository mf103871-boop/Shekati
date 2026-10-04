import Foundation
import SwiftData
import ShekatiCore

@Model
final class ChequeRecord {
    var id: UUID = UUID()
    var directionRaw: String = "incoming"
    var statusRaw: String = "pending"
    var amountMinorUnits: Int64 = 0
    var currencyCode: String = ""
    var dueDateISO: String = "2000-01-01"
    var actualDateISO: String?
    var issueDateISO: String?
    var number: String = ""
    var bank: String = ""
    var branch: String = ""
    var party: String = ""
    var accountReference: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var manualRank: Int64 = 0
    @Attribute(.externalStorage) var frontImageData: Data?
    @Attribute(.externalStorage) var backImageData: Data?
    var remindersEnabled: Bool = true
    var reminderOffsets: [Int]?
    var reminderHour: Int?
    var reminderMinute: Int?
    // Optional addition keeps the existing entity and populated stores compatible.
    // A tombstone is synced; removing it explicitly restores the original record.
    var deletedAt: Date? = nil

    init(snapshot: ChequeSnapshot, frontImageData: Data? = nil,
         backImageData: Data? = nil, remindersEnabled: Bool = true,
         reminderOffsets: [Int]? = nil, reminderHour: Int? = nil, reminderMinute: Int? = nil) {
        self.id = snapshot.id
        self.frontImageData = frontImageData
        self.backImageData = backImageData
        self.remindersEnabled = remindersEnabled
        self.reminderOffsets = reminderOffsets
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        update(from: snapshot)
    }

    var direction: ChequeDirection {
        get { ChequeDirection(rawValue: directionRaw) ?? .incoming }
        set { directionRaw = newValue.rawValue }
    }

    var status: ChequeStatus {
        get { ChequeStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var dueDate: LocalDay {
        get { LocalDay(iso: dueDateISO) ?? .today }
        set { dueDateISO = newValue.iso }
    }

    var actualDate: LocalDay? {
        get { actualDateISO.flatMap(LocalDay.init(iso:)) }
        set { actualDateISO = newValue?.iso }
    }

    var issueDate: LocalDay? {
        get { issueDateISO.flatMap(LocalDay.init(iso:)) }
        set { issueDateISO = newValue?.iso }
    }

    var isActive: Bool { deletedAt == nil }

    func canRestore(asOf date: Date = Date()) -> Bool {
        guard let deletedAt else { return false }
        let elapsed = date.timeIntervalSince(deletedAt)
        return elapsed >= 0 && elapsed < 30 * 24 * 60 * 60
    }

    var snapshot: ChequeSnapshot {
        ChequeSnapshot(id: id, direction: direction, status: status,
                       amountMinorUnits: amountMinorUnits, currencyCode: currencyCode,
                       dueDate: dueDate, actualDate: actualDate, issueDate: issueDate,
                       number: number, bank: bank, branch: branch, party: party,
                       accountReference: accountReference, notes: notes,
                       createdAt: createdAt, manualRank: manualRank)
    }

    func update(from value: ChequeSnapshot) {
        directionRaw = value.direction.rawValue
        statusRaw = value.status.rawValue
        amountMinorUnits = value.amountMinorUnits
        currencyCode = value.currencyCode
        dueDateISO = value.dueDate.iso
        actualDateISO = value.actualDate?.iso
        issueDateISO = value.issueDate?.iso
        number = value.number
        bank = value.bank
        branch = value.branch
        party = value.party
        accountReference = value.accountReference
        notes = value.notes
        createdAt = value.createdAt
        manualRank = value.manualRank
    }
}

@Model
final class AppConfiguration {
    var id: UUID = UUID()
    var currencyCode: String = ""
    var createdAt: Date = Date()

    init(currencyCode: String) { self.currencyCode = currencyCode }
}
