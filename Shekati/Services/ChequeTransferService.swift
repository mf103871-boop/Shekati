import Foundation
import SwiftData
import ShekatiCore

enum ChequeTransferError: Error, LocalizedError {
    case invalidFile, unsupportedVersion, invalidRecords, currencyMismatch, passwordTooShort, incorrectPassword
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This file is invalid or too large."
        case .unsupportedVersion: return "This backup version is not supported."
        case .invalidRecords: return "The file contains invalid cheque information."
        case .currencyMismatch: return "The file currency differs from your saved cheques."
        case .passwordTooShort: return "Use a password of at least 10 characters."
        case .incorrectPassword: return "The password is incorrect or the backup has been damaged."
        }
    }
}

struct ChequeBackupEntry: Codable, Equatable, Sendable {
    var snapshot: ChequeSnapshot
    var frontImageData: Data?
    var backImageData: Data?
    var remindersEnabled: Bool
    var reminderOffsets: [Int]?
    var reminderHour: Int?
    var reminderMinute: Int?
    var deletedAt: Date?
    var bankAccountID: UUID?
    var chequeBookID: UUID?
    var replacesChequeID: UUID?
    var ledgerBaselineStatusRaw: String?

    @MainActor init(record: ChequeRecord) {
        snapshot = record.snapshot
        frontImageData = record.frontImageData
        backImageData = record.backImageData
        remindersEnabled = record.remindersEnabled
        reminderOffsets = record.reminderOffsets
        reminderHour = record.reminderHour
        reminderMinute = record.reminderMinute
        deletedAt = record.deletedAt
        bankAccountID = record.bankAccountID
        chequeBookID = record.chequeBookID
        replacesChequeID = record.replacesChequeID
        ledgerBaselineStatusRaw = record.ledgerBaselineStatusRaw
    }

    init(snapshot: ChequeSnapshot, remindersEnabled: Bool = true) {
        self.snapshot = snapshot
        self.remindersEnabled = remindersEnabled
    }

    @MainActor func makeRecord() -> ChequeRecord {
        let record = ChequeRecord(snapshot: snapshot, frontImageData: frontImageData,
                                  backImageData: backImageData, remindersEnabled: remindersEnabled,
                                  reminderOffsets: reminderOffsets.map(deduplicatedOffsets), reminderHour: reminderHour,
                                  reminderMinute: reminderMinute)
        record.deletedAt = deletedAt
        applyFinancialLinks(to: record)
        return record
    }

    @MainActor func apply(to record: ChequeRecord) {
        record.update(from: snapshot)
        record.frontImageData = frontImageData
        record.backImageData = backImageData
        record.remindersEnabled = remindersEnabled
        record.reminderOffsets = reminderOffsets.map(deduplicatedOffsets)
        record.reminderHour = reminderHour
        record.reminderMinute = reminderMinute
        record.deletedAt = deletedAt
        applyFinancialLinks(to: record)
    }

    @MainActor private func applyFinancialLinks(to record: ChequeRecord) {
        record.bankAccountID = bankAccountID
        record.chequeBookID = chequeBookID
        record.replacesChequeID = replacesChequeID
        record.ledgerBaselineStatusRaw = ledgerBaselineStatusRaw
    }

    /// Backups may repeat reminder days. Previews and restores compare this form with stored
    /// records, so a record that was normalised on restore is reported as unchanged.
    var normalized: ChequeBackupEntry {
        var copy = self
        copy.reminderOffsets = reminderOffsets.map(deduplicatedOffsets)
        return copy
    }
}

struct GlobalReminderBackup: Codable, Equatable, Sendable {
    var offsets: [Int]
    var hour: Int
    var minute: Int
    var dailySummary: Bool
    var hideDetails: Bool
    func validate() throws {
        guard offsets.count <= 366, offsets.allSatisfy({ (0...365).contains($0) }),
              (0...23).contains(hour), (0...59).contains(minute) else { throw ChequeTransferError.invalidRecords }
    }
    @MainActor init(preferences: UserPreferences) {
        offsets = preferences.reminderOffsets; hour = preferences.reminderHour; minute = preferences.reminderMinute
        dailySummary = preferences.dailySummary; hideDetails = preferences.hideNotificationDetails
    }
    init(offsets: [Int], hour: Int, minute: Int, dailySummary: Bool, hideDetails: Bool) {
        self.offsets = offsets; self.hour = hour; self.minute = minute
        self.dailySummary = dailySummary; self.hideDetails = hideDetails
    }
    @MainActor func apply(to preferences: UserPreferences) {
        preferences.reminderOffsets = deduplicatedOffsets(offsets)
        preferences.reminderHour = hour; preferences.reminderMinute = minute
        preferences.dailySummary = dailySummary; preferences.hideNotificationDetails = hideDetails
    }
}

/// Keeps the first occurrence of each reminder day. Backups may carry repeated values, which would
/// otherwise appear as duplicate rows in Settings and in cheque details.
private func deduplicatedOffsets(_ offsets: [Int]) -> [Int] {
    var seen: Set<Int> = []
    return offsets.filter { seen.insert($0).inserted }
}

struct ChequeBackupPayload: Codable, Sendable {
    var version: Int = 1
    var createdAt: Date = Date()
    var currencyCode: String
    var records: [ChequeBackupEntry]
    var globalReminders: GlobalReminderBackup? = nil
    var banking: BankingArchive? = nil

    func validate() throws {
        guard version == 1 || version == 2 else { throw ChequeTransferError.unsupportedVersion }
        guard (version == 2) == (banking != nil) else { throw ChequeTransferError.invalidRecords }
        try globalReminders?.validate()
        guard Locale.commonISOCurrencyCodes.contains(currencyCode), records.count <= 20_000,
              Set(records.map { $0.snapshot.id }).count == records.count,
              Self.isRepresentableTimestamp(createdAt) else { throw ChequeTransferError.invalidRecords }
        for entry in records {
            let value = entry.snapshot
            let texts = [value.number, value.bank, value.branch, value.party, value.accountReference, value.notes]
            guard (version == 1 ? value.currencyCode == currencyCode : Locale.commonISOCurrencyCodes.contains(value.currencyCode)), value.amountMinorUnits > 0,
                  Self.isRepresentableTimestamp(value.createdAt),
                  entry.deletedAt.map(Self.isRepresentableTimestamp) ?? true,
                  texts.allSatisfy({ $0.utf8.count <= 100_000 }),
                  (entry.frontImageData?.count ?? 0) <= 20_000_000,
                  (entry.backImageData?.count ?? 0) <= 20_000_000,
                  entry.reminderHour.map({ (0...23).contains($0) }) ?? true,
                  entry.reminderMinute.map({ (0...59).contains($0) }) ?? true,
                  entry.reminderOffsets.map({ $0.count <= 366 && $0.allSatisfy { (0...365).contains($0) } }) ?? true,
                  value.status != .settled || value.actualDate != nil,
                  value.issueDate.map({ $0 <= value.dueDate }) ?? true,
                  value.issueDate.flatMap({ issue in value.actualDate.map { $0 >= issue } }) ?? true else {
                throw ChequeTransferError.invalidRecords
            }
        }
    }

    static func isRepresentableTimestamp(_ date: Date) -> Bool {
        // UTC 0001-01-02 through 9999-12-30. Reserve one day at each civil-date
        // boundary so a device's time zone cannot move a timestamp into year 0/10000.
        // Merely checking Double.isFinite would still allow dates such as 1e99.
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && seconds >= -62_135_510_400 && seconds < 253_402_214_400
    }
}

struct BackupRestorePreview {
    var newCount: Int
    var identicalCount: Int
    var changedCount: Int
    var recentlyDeletedCount: Int
    var newAccounts = 0
    var newBooks = 0
    var newOperations = 0
    var hasBankingChanges: Bool { newAccounts + newBooks + newOperations > 0 }
}

@MainActor
enum ChequeTransferService {
    /// CSV rows are newly created cheques. Recovering an encrypted archive is a distinct
    /// operation and must remain possible after a subscription expires.
    @discardableResult
    static func importCSV(_ payload: ChequeBackupPayload, into context: ModelContext, isPlus: Bool) throws -> Int {
        guard payload.version == 1, payload.banking == nil else { throw ChequeTransferError.invalidFile }
        try payload.validate()
        let existing = try context.fetch(FetchDescriptor<ChequeRecord>())
        let ids = Set(existing.map(\.id))
        let additions = payload.records.filter { !ids.contains($0.snapshot.id) }
        if !isPlus {
            let opening = additions.filter { $0.snapshot.isOutstanding && $0.deletedAt == nil }.count
            if opening > 0 {
                let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
                let effective = BankingLedger.effectivePositions(records: existing, events: events)
                let active = existing.filter { $0.isActive && effective[$0.id]?.isOpen == true }.count
                guard opening <= max(10 - active, 0) else { throw BankingError.chequeLimit }
            }
        }
        do {
            for entry in additions { context.insert(entry.makeRecord()) }
            try context.save()
            return additions.count
        } catch {
            context.rollback()
            throw error
        }
    }

    static func preview(_ payload: ChequeBackupPayload, existing: [ChequeRecord], context: ModelContext? = nil) throws -> BackupRestorePreview {
        try payload.validate()
        try payload.banking?.validate(records: payload.records)
        let byID = Dictionary(existing.map { ($0.id, ChequeBackupEntry(record: $0)) }, uniquingKeysWith: { first, _ in first })
        var preview = BackupRestorePreview(newCount: 0, identicalCount: 0, changedCount: 0,
                                          recentlyDeletedCount: payload.records.filter { $0.deletedAt != nil }.count)
        for entry in payload.records.map(\.normalized) {
            if let old = byID[entry.snapshot.id] {
                if old == entry { preview.identicalCount += 1 }
                else { preview.changedCount += 1 }
            } else { preview.newCount += 1 }
        }
        if let archive = payload.banking, let context {
            let savedAccounts = Set(try context.fetch(FetchDescriptor<BankAccountRecord>()).map(\.id))
            let savedBooks = Set(try context.fetch(FetchDescriptor<ChequeBookRecord>()).map(\.id))
            let savedEvents = Set(try context.fetch(FetchDescriptor<LedgerEventRecord>()).map(\.id))
            preview.newAccounts = archive.accounts.filter { !savedAccounts.contains($0.id) }.count
            preview.newBooks = archive.books.filter { !savedBooks.contains($0.id) }.count
            preview.newOperations = archive.events.filter { !savedEvents.contains($0.id) }.count
        }
        return preview
    }

    @discardableResult
    static func restore(_ payload: ChequeBackupPayload, into context: ModelContext,
                        replaceExisting: Bool = false) throws -> Int {
        // Validate everything before touching the live context. Save is one transaction.
        try payload.validate()
        let existing = try context.fetch(FetchDescriptor<ChequeRecord>())
        try payload.banking?.validate(records: payload.records)
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        do {
            for var entry in payload.records.map(\.normalized) {
                if let record = byID[entry.snapshot.id] {
                    if payload.version == 1 && !replaceExisting { continue }
                    if record.ledgerBaselineStatusRaw != nil || record.bankAccountID != nil {
                        // Never erase a newer journal with an older backup, including when replacing metadata.
                        guard entry.bankAccountID == nil || record.bankAccountID == entry.bankAccountID,
                              entry.ledgerBaselineStatusRaw == nil || record.ledgerBaselineStatusRaw == nil || record.ledgerBaselineStatusRaw == entry.ledgerBaselineStatusRaw,
                              entry.replacesChequeID == nil || record.replacesChequeID == entry.replacesChequeID,
                              record.amountMinorUnits == entry.snapshot.amountMinorUnits,
                              record.currencyCode == entry.snapshot.currencyCode,
                              record.direction == entry.snapshot.direction else { throw ChequeTransferError.invalidRecords }
                        entry.bankAccountID = record.bankAccountID ?? entry.bankAccountID
                        entry.chequeBookID = record.chequeBookID ?? entry.chequeBookID
                        entry.ledgerBaselineStatusRaw = record.ledgerBaselineStatusRaw ?? entry.ledgerBaselineStatusRaw
                        entry.replacesChequeID = record.replacesChequeID ?? entry.replacesChequeID
                        if record.ledgerBaselineStatusRaw == nil { record.ledgerBaselineStatusRaw = entry.ledgerBaselineStatusRaw }
                    } else if !replaceExisting && (entry.ledgerBaselineStatusRaw != nil || entry.bankAccountID != nil) {
                        guard record.amountMinorUnits == entry.snapshot.amountMinorUnits,
                              record.currencyCode == entry.snapshot.currencyCode,
                              record.direction == entry.snapshot.direction else { throw ChequeTransferError.invalidRecords }
                        record.bankAccountID = entry.bankAccountID
                        record.chequeBookID = entry.chequeBookID
                        record.ledgerBaselineStatusRaw = entry.ledgerBaselineStatusRaw
                        record.replacesChequeID = entry.replacesChequeID
                        changed += 1
                    }
                    if replaceExisting && ChequeBackupEntry(record: record) != entry {
                        entry.apply(to: record); changed += 1
                    }
                } else {
                    context.insert(entry.makeRecord()); changed += 1
                }
            }
            try payload.banking?.merge(into: context)
            let touched = Set(payload.records.map(\.snapshot.id))
            let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
            let eventGroups = Dictionary(grouping: events, by: \.chequeID)
            for record in try context.fetch(FetchDescriptor<ChequeRecord>()) where touched.contains(record.id) {
                guard let journal = eventGroups[record.id], !journal.isEmpty else { continue }
                BankingLedger.reflect(BankingLedger.position(for: record, events: journal), record: record)
            }
            let configurations = try context.fetch(FetchDescriptor<AppConfiguration>(sortBy: [SortDescriptor(\.createdAt)]))
            if configurations.isEmpty { context.insert(AppConfiguration(currencyCode: payload.currencyCode)) }
            try context.save()
            return changed
        } catch {
            context.rollback()
            throw error
        }
    }

    static func validateCurrency(_ code: String, existing: [ChequeRecord]) throws {
        guard existing.allSatisfy({ $0.currencyCode == code }) else { throw ChequeTransferError.currencyMismatch }
    }
}
