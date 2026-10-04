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

    @MainActor init(record: ChequeRecord) {
        snapshot = record.snapshot
        frontImageData = record.frontImageData
        backImageData = record.backImageData
        remindersEnabled = record.remindersEnabled
        reminderOffsets = record.reminderOffsets
        reminderHour = record.reminderHour
        reminderMinute = record.reminderMinute
        deletedAt = record.deletedAt
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

    func validate() throws {
        guard version == 1 else { throw ChequeTransferError.unsupportedVersion }
        try globalReminders?.validate()
        guard Locale.commonISOCurrencyCodes.contains(currencyCode), records.count <= 20_000,
              Set(records.map { $0.snapshot.id }).count == records.count,
              Self.isRepresentableTimestamp(createdAt) else { throw ChequeTransferError.invalidRecords }
        for entry in records {
            let value = entry.snapshot
            let texts = [value.number, value.bank, value.branch, value.party, value.accountReference, value.notes]
            guard value.currencyCode == currencyCode, value.amountMinorUnits > 0,
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

    private static func isRepresentableTimestamp(_ date: Date) -> Bool {
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
}

@MainActor
enum ChequeTransferService {
    static func preview(_ payload: ChequeBackupPayload, existing: [ChequeRecord]) throws -> BackupRestorePreview {
        try payload.validate()
        try validateCurrency(payload.currencyCode, existing: existing)
        let byID = Dictionary(existing.map { ($0.id, ChequeBackupEntry(record: $0)) }, uniquingKeysWith: { first, _ in first })
        var preview = BackupRestorePreview(newCount: 0, identicalCount: 0, changedCount: 0,
                                          recentlyDeletedCount: payload.records.filter { $0.deletedAt != nil }.count)
        for entry in payload.records {
            if let old = byID[entry.snapshot.id] {
                if old == entry { preview.identicalCount += 1 }
                else { preview.changedCount += 1 }
            } else { preview.newCount += 1 }
        }
        return preview
    }

    @discardableResult
    static func restore(_ payload: ChequeBackupPayload, into context: ModelContext,
                        replaceExisting: Bool = false) throws -> Int {
        // Validate everything before touching the live context. Save is one transaction.
        try payload.validate()
        let existing = try context.fetch(FetchDescriptor<ChequeRecord>())
        try validateCurrency(payload.currencyCode, existing: existing)
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        do {
            for entry in payload.records {
                if let record = byID[entry.snapshot.id] {
                    if replaceExisting && ChequeBackupEntry(record: record) != entry {
                        entry.apply(to: record); changed += 1
                    }
                } else {
                    context.insert(entry.makeRecord()); changed += 1
                }
            }
            let configurations = try context.fetch(FetchDescriptor<AppConfiguration>(sortBy: [SortDescriptor(\.createdAt)]))
            if let configuration = configurations.first { configuration.currencyCode = payload.currencyCode }
            else { context.insert(AppConfiguration(currencyCode: payload.currencyCode)) }
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
