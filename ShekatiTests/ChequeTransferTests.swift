import Foundation
import XCTest
import SwiftData
import CryptoKit
import PDFKit
import ShekatiCore
@testable import Shekati

@MainActor
final class ChequeTransferTests: XCTestCase {
    func testEncryptedBackupRestoresExactMoneyPhotosRemindersTombstoneAndIdentity() throws {
        let record = makeRecord()
        record.frontImageData = Data([1, 2, 3, 4])
        record.backImageData = Data([5, 6, 7])
        record.remindersEnabled = false
        record.reminderOffsets = [14, 3, 0]
        record.reminderHour = 8; record.reminderMinute = 25
        record.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(record: record)])
        let encrypted = try EncryptedBackup.encrypt(original, password: "اختبار كلمة السر 123")
        XCTAssertFalse(String(data: encrypted, encoding: .utf8)?.contains("000123") ?? false)
        XCTAssertFalse(encrypted.range(of: Data(record.party.utf8)) != nil)
        let restored = try EncryptedBackup.decrypt(encrypted, password: "اختبار كلمة السر 123")
        XCTAssertEqual(restored.records, original.records)
        let context = try makeContext()
        XCTAssertEqual(try ChequeTransferService.restore(restored, into: context), 1)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeRecord>()).first)
        XCTAssertEqual(ChequeBackupEntry(record: saved), original.records.first)
        XCTAssertEqual(saved.number, "000123")
        XCTAssertEqual(saved.amountMinorUnits, 12_345)
        XCTAssertFalse(saved.isActive)
        let configurations = try context.fetch(FetchDescriptor<AppConfiguration>())
        XCTAssertEqual(configurations.first?.currencyCode, "JOD")
    }

    func testBackupRejectsWrongPasswordTamperingAndHostileKDFHeader() throws {
        let payload = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(record: makeRecord())])
        let encrypted = try EncryptedBackup.encrypt(payload, password: "strong-password-123")
        XCTAssertThrowsError(try EncryptedBackup.decrypt(encrypted, password: "wrong-password"))
        var damaged = encrypted
        damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try EncryptedBackup.decrypt(damaged, password: "strong-password-123"))
        var hostile = encrypted
        hostile[24] = 255
        XCTAssertThrowsError(try EncryptedBackup.decrypt(hostile, password: "strong-password-123"))
        XCTAssertThrowsError(try EncryptedBackup.encrypt(payload, password: "short"))
    }

    func testSamePasswordProducesDifferentEncryptedFiles() throws {
        let payload = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(record: makeRecord())])
        let first = try EncryptedBackup.encrypt(payload, password: "same-password-123")
        let second = try EncryptedBackup.encrypt(payload, password: "same-password-123")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first[8..<24], second[8..<24])
        XCTAssertEqual(try EncryptedBackup.decrypt(first, password: "same-password-123").records,
                       try EncryptedBackup.decrypt(second, password: "same-password-123").records)
    }

    func testGlobalReminderDefaultsRoundTripAndInvalidDateRelationshipsAreRejected() throws {
        let defaults = GlobalReminderBackup(offsets: [14, 3, 1, 0], hour: 7, minute: 45,
                                            dailySummary: true, hideDetails: true)
        var payload = ChequeBackupPayload(currencyCode: "JOD", records: [ChequeBackupEntry(record: makeRecord())],
                                         globalReminders: defaults)
        let encrypted = try EncryptedBackup.encrypt(payload, password: "restore-reminders-123")
        XCTAssertEqual(try EncryptedBackup.decrypt(encrypted, password: "restore-reminders-123").globalReminders, defaults)
        let suite = "Shekati-transfer-tests-\(UUID().uuidString)"
        let local = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { local.removePersistentDomain(forName: suite) }
        let preferences = UserPreferences(defaults: local)
        preferences.appLockEnabled = true; preferences.language = .arabic
        defaults.apply(to: preferences)
        XCTAssertEqual(preferences.reminderOffsets, [14, 3, 1, 0])
        XCTAssertEqual(preferences.reminderHour, 7); XCTAssertEqual(preferences.reminderMinute, 45)
        XCTAssertTrue(preferences.dailySummary); XCTAssertTrue(preferences.hideNotificationDetails)
        XCTAssertTrue(preferences.appLockEnabled); XCTAssertEqual(preferences.language, .arabic)
        payload.records[0].snapshot.issueDate = LocalDay(iso: "2026-10-21")
        XCTAssertThrowsError(try payload.validate())
        payload.records[0].snapshot.issueDate = LocalDay(iso: "2026-10-01")
        payload.records[0].snapshot.actualDate = LocalDay(iso: "2026-09-30")
        XCTAssertThrowsError(try payload.validate())
        payload.records[0].snapshot.actualDate = nil
        payload.globalReminders?.hour = 25
        XCTAssertThrowsError(try payload.validate())
    }

    func testOversizedBackupIsRejectedBeforeAllocatingJSONImageArchive() throws {
        let sharedImage = Data(repeating: 7, count: 1_000_000)
        let entries = (0..<200).map { _ -> ChequeBackupEntry in
            var entry = ChequeBackupEntry(record: makeRecord())
            entry.frontImageData = sharedImage
            return entry
        }
        let payload = ChequeBackupPayload(currencyCode: "JOD", records: entries)
        XCTAssertThrowsError(try EncryptedBackup.validateEstimatedSize(payload))
        XCTAssertThrowsError(try EncryptedBackup.encrypt(payload, password: "large-backup-password"))
    }

    func testRestoreSkipsExistingByDefaultAndExplicitlyReplacesMatchingIdentity() throws {
        let context = try makeContext()
        let existing = makeRecord(); context.insert(existing); try context.save()
        var replacement = ChequeBackupEntry(record: existing)
        replacement.snapshot.party = "Changed demo"
        replacement.frontImageData = Data([9, 8, 7])
        let payload = ChequeBackupPayload(currencyCode: "JOD", records: [replacement])
        let preview = try ChequeTransferService.preview(payload, existing: [existing])
        XCTAssertEqual(preview.newCount, 0); XCTAssertEqual(preview.changedCount, 1)
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: context), 0)
        XCTAssertNotEqual(existing.party, "Changed demo")
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: context, replaceExisting: true), 1)
        XCTAssertEqual(existing.id, replacement.snapshot.id)
        XCTAssertEqual(existing.party, "Changed demo")
        XCTAssertEqual(existing.frontImageData, Data([9, 8, 7]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChequeRecord>()).count, 1)
    }

    func testInvalidPayloadAndCurrencyMismatchCannotPartiallyChangeStore() throws {
        let context = try makeContext()
        let existing = makeRecord(); context.insert(existing); try context.save()
        var invalid = ChequeBackupEntry(record: makeRecord())
        invalid.snapshot.amountMinorUnits = 0
        let valid = ChequeBackupEntry(record: makeRecord())
        XCTAssertThrowsError(try ChequeTransferService.restore(
            ChequeBackupPayload(currencyCode: "JOD", records: [valid, invalid]), into: context))
        var foreign = valid
        foreign.snapshot.currencyCode = "USD"
        XCTAssertThrowsError(try ChequeTransferService.restore(
            ChequeBackupPayload(currencyCode: "USD", records: [foreign]), into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChequeRecord>()).count, 1)
        XCTAssertEqual(existing.currencyCode, "JOD")
        let duplicatedID = ChequeBackupPayload(currencyCode: "JOD", records: [valid, valid])
        XCTAssertThrowsError(try duplicatedID.validate())
    }

    func testExtremeAndNonfiniteBackupTimestampsCannotPartiallyChangeStore() throws {
        let context = try makeContext()
        let existing = makeRecord(); context.insert(existing); try context.save()
        let original = existing.snapshot
        let newEntry = ChequeBackupEntry(record: makeRecord())
        let invalidSeconds: [TimeInterval] = [1e99, -1e99, .infinity, -.infinity, .nan,
                                             -62_135_596_800, 253_402_300_800]
        for seconds in invalidSeconds {
            let invalidDate = Date(timeIntervalSince1970: seconds)
            var recordCreated = ChequeBackupEntry(record: makeRecord())
            recordCreated.snapshot.createdAt = invalidDate
            var deletion = ChequeBackupEntry(record: makeRecord())
            deletion.deletedAt = invalidDate
            let recordPayload = ChequeBackupPayload(currencyCode: "JOD", records: [newEntry, recordCreated])
            let deletionPayload = ChequeBackupPayload(currencyCode: "JOD", records: [newEntry, deletion])
            var backupCreated = ChequeBackupPayload(currencyCode: "JOD", records: [newEntry])
            backupCreated.createdAt = invalidDate
            for payload in [recordPayload, deletionPayload, backupCreated] {
                XCTAssertThrowsError(try payload.validate())
                XCTAssertThrowsError(try ChequeTransferService.restore(payload, into: context, replaceExisting: true))
                XCTAssertEqual(try context.fetch(FetchDescriptor<ChequeRecord>()).count, 1)
                XCTAssertEqual(existing.snapshot, original)
                XCTAssertTrue(try context.fetch(FetchDescriptor<AppConfiguration>()).isEmpty)
            }
        }
    }

    func testHistoricalAndTimezoneSafeBoundaryTimestampsRemainRepresentable() throws {
        let context = try makeContext()
        let historical = Date(timeIntervalSince1970: -2_208_988_800) // 1900-01-01 UTC
        var entry = ChequeBackupEntry(record: makeRecord())
        entry.snapshot.createdAt = historical
        entry.deletedAt = historical.addingTimeInterval(86_400)
        var payload = ChequeBackupPayload(currencyCode: "JOD", records: [entry])
        payload.createdAt = historical.addingTimeInterval(2 * 86_400)
        XCTAssertNoThrow(try payload.validate())
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: context), 1)
        let loaded = try XCTUnwrap(context.fetch(FetchDescriptor<ChequeRecord>()).first)
        XCTAssertEqual(loaded.createdAt, historical)
        XCTAssertEqual(loaded.deletedAt, historical.addingTimeInterval(86_400))
        for seconds in [TimeInterval(-62_135_510_400), TimeInterval(253_402_214_399)] {
            var boundary = entry
            boundary.snapshot.createdAt = Date(timeIntervalSince1970: seconds)
            boundary.deletedAt = boundary.snapshot.createdAt
            payload.createdAt = boundary.snapshot.createdAt
            payload.records = [boundary]
            XCTAssertNoThrow(try payload.validate())
        }
    }

    func testCSVExportImportPreservesZerosArabicQuotesAndFormulaLikeText() throws {
        var snapshot = makeRecord().snapshot
        snapshot.notes = "=1+1\nنص عربي, \"ملاحظة\""
        snapshot.number = "000123"
        snapshot.accountReference = "000004"
        snapshot.party = "'=cmd"
        let exported = ChequeCSV.export([snapshot])
        XCTAssertEqual(Array(exported.prefix(3)), [0xEF, 0xBB, 0xBF])
        let decoded = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertTrue(decoded.contains("\"'000123\""))
        XCTAssertTrue(decoded.contains("\"'=1+1"))
        let preview = try ChequeCSV.preview(exported, currencyCode: "JOD", existing: [])
        XCTAssertTrue(preview.issues.isEmpty)
        let value = try XCTUnwrap(preview.rows.first?.snapshot)
        XCTAssertEqual(value.number, snapshot.number)
        XCTAssertEqual(value.accountReference, snapshot.accountReference)
        XCTAssertEqual(value.notes, snapshot.notes)
        XCTAssertEqual(value.party, snapshot.party)
        XCTAssertEqual(value.amountMinorUnits, 12_345)
        XCTAssertEqual(value.dueDate, snapshot.dueDate)
    }

    func testCSVRejectsAmbiguousDatesOverprecisionAndMissingSettlementDates() throws {
        let header = "direction,status,amount,currency,due_date,number\n"
        let rows = ["incoming,pending,12.3456,JOD,2026-10-20,00001",
                    "incoming,pending,12.345,JOD,20/10/2026,00002",
                    "outgoing,settled,12.345,JOD,2026-10-20,00003",
                    "incoming,pending,12.345,USD,2026-10-20,00004",
                    "incoming,pending,12.345,JOD,2026-10-20,00005"]
        let preview = try ChequeCSV.preview(Data((header + rows.joined(separator: "\n")).utf8), currencyCode: "JOD", existing: [])
        XCTAssertEqual(preview.issues.count, 4)
        XCTAssertEqual(preview.rows.count, 1)
        XCTAssertEqual(preview.rows.first?.snapshot.number, "00005")
        XCTAssertEqual(preview.rows.first?.snapshot.amountMinorUnits, 12_345)
    }

    func testCSVFlagsDuplicatesAgainstStoreAndEarlierImportedRows() throws {
        let existing = makeRecord().snapshot
        let exported = ChequeCSV.export([existing, existing])
        let preview = try ChequeCSV.preview(exported, currencyCode: "JOD", existing: [existing])
        XCTAssertEqual(preview.duplicateCount, 2)
        XCTAssertTrue(preview.payload(includeDuplicates: false).records.isEmpty)
        XCTAssertEqual(preview.payload(includeDuplicates: true).records.count, 2)
        let withinFile = try ChequeCSV.preview(exported, currencyCode: "JOD", existing: [])
        XCTAssertEqual(withinFile.duplicateCount, 1)
        XCTAssertEqual(withinFile.payload(includeDuplicates: false).records.count, 1)
    }

    func testCSVIndexMatchesDuplicatePolicyForArabicNumbersBanksAndNumberlessCheques() throws {
        let base = makeRecord().snapshot
        var arabicNumber = base; arabicNumber.id = UUID(); arabicNumber.number = "٠٠٠١٢٣"
        var anotherBank = base; anotherBank.id = UUID(); anotherBank.bank = "Another bank"
        var numberless = base; numberless.id = UUID(); numberless.number = ""
        var numberlessMatch = numberless; numberlessMatch.id = UUID()
        let candidates = [arabicNumber, anotherBank, numberlessMatch]
        let existing = [base, numberless]
        let expected = Set(candidates.filter {
            !ChequeEntryAssistance.probableDuplicateIDs(for: $0, among: existing).isEmpty
        }.map(\.id))
        XCTAssertEqual(ChequeCSV.duplicateIDs(for: candidates, existing: existing), expected)
        XCTAssertEqual(expected, [arabicNumber.id, numberlessMatch.id])
    }

    func testCSVHandlesZeroAndThreeDecimalCurrenciesExactlyAndRejectsMalformedQuotes() throws {
        let jpy = Data("direction,amount,due_date,number\r\nincoming,123,2026-10-20,00001\r\n".utf8)
        let parsedJPY = try ChequeCSV.preview(jpy, currencyCode: "JPY", existing: [])
        XCTAssertEqual(parsedJPY.rows.first?.snapshot.amountMinorUnits, 123)
        let jpyFraction = Data("direction,amount,due_date\nincoming,123.1,2026-10-20\n".utf8)
        XCTAssertEqual(try ChequeCSV.preview(jpyFraction, currencyCode: "JPY", existing: []).issues.count, 1)
        let malformed = Data("direction,amount,due_date\nincoming,\"12,2026-10-20".utf8)
        XCTAssertThrowsError(try ChequeCSV.preview(malformed, currencyCode: "JOD", existing: []))
        let duplicatedHeader = Data("direction,amount,due_date,direction\nincoming,12,2026-10-20,incoming".utf8)
        XCTAssertThrowsError(try ChequeCSV.preview(duplicatedHeader, currencyCode: "JOD", existing: []))
    }

    func testSoftDeleteRetainsPhotosRestoresWithinWindowAndDoesNotRestoreAfter30Days() throws {
        let context = try makeContext()
        let record = makeRecord(); record.frontImageData = Data([7, 6, 5])
        context.insert(record); try context.save()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        record.deletedAt = now; try context.save()
        XCTAssertFalse(record.isActive)
        XCTAssertTrue(record.canRestore(asOf: now.addingTimeInterval(29 * 86_400)))
        XCTAssertFalse(record.canRestore(asOf: now.addingTimeInterval(30 * 86_400)))
        XCTAssertFalse(record.canRestore(asOf: now.addingTimeInterval(-1)))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChequeRecord>()).count, 1)
        XCTAssertEqual(record.frontImageData, Data([7, 6, 5]))
        record.deletedAt = nil; try context.save()
        XCTAssertTrue(record.isActive)
        XCTAssertFalse(record.canRestore(asOf: now))
        XCTAssertEqual(record.number, "000123")
        XCTAssertEqual(record.frontImageData, Data([7, 6, 5]))
    }

    func testPDFUsesFilteredInputAndProducesMultiplePagesWithArabicAndLeadingZeros() throws {
        let base = makeRecord().snapshot
        let rows = (0..<100).map { index -> ChequeSnapshot in
            var value = base; value.id = UUID(); value.number = String(format: "%06d", index + 1)
            value.direction = index.isMultiple(of: 2) ? .incoming : .outgoing
            if index == 0 {
                value.party = "اسم تجريبي طويل جدًا لفحص كشف الشيكات على صفحات PDF " + String(repeating: "معلومات إضافية ", count: 10) + "PARTY-TAIL"
            }
            if index == 1 {
                value.bank = "بنك تجريبي باسم طويل لفحص وضوح التفاصيل " + String(repeating: "فرع تجريبي ", count: 10) + "BANK-TAIL"
            }
            return value
        }
        let english = ChequePDFReport.generate(cheques: rows, language: .english)
        let englishAttachment = XCTAttachment(data: english, uniformTypeIdentifier: "com.adobe.pdf")
        englishAttachment.name = "build6-English-cheque-report"; englishAttachment.lifetime = .keepAlways
        add(englishAttachment)
        let arabic = ChequePDFReport.generate(cheques: rows, language: .arabic)
        let arabicAttachment = XCTAttachment(data: arabic, uniformTypeIdentifier: "com.adobe.pdf")
        arabicAttachment.name = "build6-Arabic-cheque-report"; arabicAttachment.lifetime = .keepAlways
        add(arabicAttachment)
        let pdf = try XCTUnwrap(PDFDocument(data: english))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("000001") ?? false)
        XCTAssertTrue(pdf.string?.contains("000100") ?? false)
        XCTAssertTrue(pdf.string?.contains("Incoming") ?? false)
        XCTAssertTrue(pdf.string?.contains("Outgoing") ?? false)
        XCTAssertTrue(pdf.string?.contains("PARTY-TAIL") ?? false)
        XCTAssertTrue(pdf.string?.contains("BANK-TAIL") ?? false)
        let arabicPDF = try XCTUnwrap(PDFDocument(data: arabic))
        XCTAssertTrue(arabicPDF.string?.contains("PARTY-TAIL") ?? false)
        XCTAssertTrue(arabicPDF.string?.contains("BANK-TAIL") ?? false)
        XCTAssertTrue(pdf.string?.contains(DisplayFormatting.day(rows[0].dueDate, locale: AppLanguage.english.locale)) ?? false)
        let filteredBytes = ChequePDFReport.generate(cheques: [rows[0]], language: .arabic)
        let filteredAttachment = XCTAttachment(data: filteredBytes, uniformTypeIdentifier: "com.adobe.pdf")
        filteredAttachment.name = "build6-Arabic-filtered-one-cheque-report"; filteredAttachment.lifetime = .keepAlways
        add(filteredAttachment)
        let filtered = try XCTUnwrap(PDFDocument(data: filteredBytes))
        XCTAssertEqual(filtered.pageCount, 1)
        XCTAssertTrue(filtered.string?.contains("000001") ?? false)
        XCTAssertTrue(filtered.string?.contains("PARTY-TAIL") ?? false)
        XCTAssertFalse(filtered.string?.contains("000100") ?? true)
    }

    func testPDFContinuesExtraordinaryWrappedChequeAcrossPagesWithoutLosingTailMarkers() throws {
        var huge = makeRecord().snapshot
        huge.number = "000777"
        huge.party = String(repeating: "اسم تجريبي عربي كامل مع تفاصيل طويلة 👨‍👩‍👧‍👦 لقياس الاستمرار بين الصفحات. ", count: 90) + "PARTY-END-MARKER"
        huge.bank = String(repeating: "بنك تجريبي وفرع طويل وتفاصيل كاملة للاستمرار. ", count: 90) + "BANK-END-MARKER"
        for language in [AppLanguage.arabic, AppLanguage.english] {
            let data = ChequePDFReport.generate(cheques: [huge], language: language)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = language == .arabic ? "build6-Arabic-long-cheque-continuation" : "build6-English-long-cheque-continuation"
            attachment.lifetime = .keepAlways; add(attachment)
            let document = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertGreaterThan(document.pageCount, 2)
            let text = try XCTUnwrap(document.string)
            XCTAssertTrue(text.contains("PARTY-END-MARKER"))
            XCTAssertTrue(text.contains("BANK-END-MARKER"))
            XCTAssertTrue(text.contains("000777"))
            for index in 0..<document.pageCount {
                let pageText = try XCTUnwrap(document.page(at: index)?.string)
                XCTAssertTrue(pageText.contains("12.345"), "Amount must repeat on continuation page \(index + 1)")
                XCTAssertTrue(pageText.contains(DisplayFormatting.day(huge.dueDate, locale: language.locale)))
            }
        }
    }

    private func makeRecord() -> ChequeRecord {
        ChequeRecord(snapshot: ChequeSnapshot(direction: .outgoing, amountMinorUnits: 12_345,
            currencyCode: "JOD", dueDate: LocalDay(iso: "2026-10-20")!,
            number: "000123", bank: "Demo bank", party: "شيك تجريبي",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), manualRank: 9))
    }
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container); context.autosaveEnabled = false
        return context
    }
}
