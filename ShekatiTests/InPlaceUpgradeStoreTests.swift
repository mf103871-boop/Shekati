import XCTest
import SwiftData
import CryptoKit
import UIKit
import ShekatiCore
@testable import Shekati

@MainActor
final class InPlaceUpgradeStoreTests: XCTestCase {
    func testReadRealApplicationStoreWithoutWriting() throws {
        let path = URL.applicationSupportDirectory.appending(path: "Shekati/Shekati.store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let schema = Schema([ChequeRecord.self, AppConfiguration.self, BankAccountRecord.self, ChequeBookRecord.self, LedgerEventRecord.self])
        let conf = ModelConfiguration("Shekati", schema: schema, url: path, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [conf])
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let accounts = try ctx.fetch(FetchDescriptor<BankAccountRecord>())
        let cheques = try ctx.fetch(FetchDescriptor<ChequeRecord>())
        let events = try ctx.fetch(FetchDescriptor<LedgerEventRecord>()).sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(accounts.count,1)
        XCTAssertEqual(cheques.count,1)
        XCTAssertEqual(events.count,2)
        let account = try XCTUnwrap(accounts.first)
        let c = try XCTUnwrap(cheques.first)
        XCTAssertEqual(c.number,"000417")
        XCTAssertEqual(c.party,"Upgrade Studio")
        XCTAssertEqual(c.bankAccountID,account.id)
        XCTAssertEqual(c.currencyCode,"USD")
        XCTAssertEqual(c.amountMinorUnits,12550)
        let outlook = try BankingLedger.outlook(account: account, records: cheques, events: events, today: .today)
        XCTAssertEqual(outlook.recorded,12550)
        let pos = BankingLedger.position(for: c, events: events)
        XCTAssertEqual(pos.paid,12550)
        XCTAssertEqual(pos.remaining,0)
        func imageDetails(_ bytes: Data?) throws -> [String: Any] {
            let data = try XCTUnwrap(bytes)
            let im = try XCTUnwrap(UIImage(data: data)?.cgImage)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let ctx = try XCTUnwrap(CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:space,bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            ctx.interpolationQuality = .high
            ctx.draw(im, in: CGRect(x:0,y:0,width:1,height:1))
            let p = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
            let color = Int(p[0]) > Int(p[2]) + 45 ? "red" : (Int(p[2]) > Int(p[0]) + 45 ? "blue" : "other")
            return ["sha256": SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(), "bytes":data.count, "width":im.width, "height":im.height, "color":color]
        }
        let front = try imageDetails(c.frontImageData), back = try imageDetails(c.backImageData)
        XCTAssertEqual(Set([front["color"] as? String,back["color"] as? String].compactMap { $0 }), Set(["blue","red"]))
        let operations = events.map { ["id":$0.id.uuidString, "kind":$0.kindRaw, "day":$0.dayISO, "amountMinor":String($0.amountMinor), "account":$0.accountID?.uuidString ?? "", "cheque":$0.chequeID?.uuidString ?? ""] }
        let result: [String: Any] = ["account":account.id.uuidString,"accountName":account.name,"openingMinor":account.openingMinor, "currency":account.currencyCode, "chequeID":c.id.uuidString, "number":c.number, "party":c.party, "dueDate":c.dueDateISO, "amountMinor":c.amountMinorUnits,"recordedMinor":outlook.recorded,"paidMinor":pos.paid,"remainingMinor":pos.remaining,"events":operations,"front":front,"back":back]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        let export = XCTAttachment(data: bytes, uniformTypeIdentifier:"public.json")
        export.name = "Persisted-upgrade-fixture-build-" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown")
        export.lifetime = .keepAlways
        add(export)
    }
}
