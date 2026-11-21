import CryptoKit
import Foundation
import SwiftData
import UIKit
import XCTest
import ShekatiCore
@testable import Shekati

@MainActor
final class LegacyUpgradeStoreTests: XCTestCase {
    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func persistentContainer() throws -> ModelContainer {
        let url = URL.applicationSupportDirectory.appending(path:"Shekati/Shekati.store")
        #if LEGACY_BUILD9
        let schema = Schema([ChequeRecord.self, AppConfiguration.self])
        #else
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        #endif
        let conf = ModelConfiguration("Shekati", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [conf])
    }

    #if LEGACY_BUILD9
    func testSeedThroughBuild9RestoreService() throws {
        let actual = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String)
        XCTAssertEqual(actual,"9")
        let bytes = try XCTUnwrap(Data(base64Encoded: legacyArchiveBase64))
        XCTAssertEqual(digest(bytes),"bd6c1333d6ae6bf29b1e9fe0a338cb3b9bf51426f190e87c07ba25bbd7ea631f")
        let payload = try EncryptedBackup.decrypt(bytes, password:"Shekati-Demo-2026")
        XCTAssertEqual(payload.version,1)
        let container = try persistentContainer()
        let ctx = ModelContext(container)
        let prior = try ctx.fetch(FetchDescriptor<ChequeRecord>())
        XCTAssertTrue(prior.isEmpty)
        _ = try ChequeTransferService.preview(payload, existing: prior)
        XCTAssertEqual(try ChequeTransferService.restore(payload, into: ctx),6)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ChequeRecord>()),6)
    }
    #endif

    func testReadPersistedLegacyData() throws {
        let container = try persistentContainer()
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let records = try ctx.fetch(FetchDescriptor<ChequeRecord>()).sorted { $0.number < $1.number }
        let config = try XCTUnwrap(ctx.fetch(FetchDescriptor<AppConfiguration>()).first)
        XCTAssertEqual(records.count,6)
        XCTAssertEqual(config.currencyCode,"JOD")
        let open = records.filter { $0.deletedAt == nil && $0.snapshot.isOutstanding }
        XCTAssertEqual(open.count,3)
        let incoming = open.filter { $0.direction == .incoming }.reduce(Int64(0)) { $0 + $1.amountMinorUnits }
        let outgoing = open.filter { $0.direction == .outgoing }.reduce(Int64(0)) { $0 + $1.amountMinorUnits }
        XCTAssertEqual(incoming,1650200); XCTAssertEqual(outgoing,3200050)
        let scanned = try XCTUnwrap(records.first { $0.number == "004182" })
        let front = try XCTUnwrap(scanned.frontImageData)
        let back = try XCTUnwrap(scanned.backImageData)
        XCTAssertEqual(digest(front),"481cfe7f33e233900435fd26fff006bee047542a1c965fdea1f45a422ea8b17c")
        XCTAssertEqual(digest(back),"9450f838068056053d6d9684abed7e64a63ce24d027fe4b328df5d6a066958fc")
        XCTAssertEqual(UIImage(data:front)?.cgImage?.width,320)
        XCTAssertEqual(UIImage(data:back)?.cgImage?.height,140)
        XCTAssertEqual(scanned.reminderOffsets,[7,3,1,0]); XCTAssertEqual(scanned.reminderHour,9); XCTAssertEqual(scanned.reminderMinute,15)
        XCTAssertEqual(records.first { $0.number == "000013" }?.actualDateISO,"2026-11-11")
        XCTAssertEqual(records.first { $0.number == "000014" }?.actualDateISO,"2026-11-12")
        XCTAssertEqual(records.first { $0.number == "000207" }?.status,.returned)
        XCTAssertEqual(records.first { $0.number == "000900" }?.deletedAt?.timeIntervalSince1970,1795086000)
        #if !LEGACY_BUILD9
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<BankAccountRecord>()),0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LedgerEventRecord>()),0)
        XCTAssertTrue(records.allSatisfy { $0.bankAccountID == nil })
        #endif
        var details = [[String: Any]]()
        for c in records {
            let row: [String: Any] = ["id":c.id.uuidString,"number":c.number,"party":c.party,"direction":c.directionRaw,
                 "status":c.statusRaw,"currency":c.currencyCode,"amount":c.amountMinorUnits,"due":c.dueDateISO,"paid":c.actualDateISO ?? "",
                 "issued":c.issueDateISO ?? "","deletedUnix":c.deletedAt?.timeIntervalSince1970 ?? 0,
                 "createdUnix":c.createdAt.timeIntervalSince1970,"note":c.notes,"rank":c.manualRank,"reminders":c.remindersEnabled]
            details.append(row)
        }
        let payload: [String: Any] = ["currency": config.currencyCode,"incomingMinor":incoming, "outgoingMinor":outgoing,
             "cheques":details,"frontSHA256":digest(front),"backSHA256":digest(back),"offsets":scanned.reminderOffsets ?? [],
             "reminderHour":scanned.reminderHour ?? -1,"reminderMinute":scanned.reminderMinute ?? -1]
        let bytes = try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys,.prettyPrinted])
        let a = XCTAttachment(data:bytes, uniformTypeIdentifier:"public.json")
        a.name = "Legacy-persisted-build-" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown")
        a.lifetime = .keepAlways; add(a)
    }
}
