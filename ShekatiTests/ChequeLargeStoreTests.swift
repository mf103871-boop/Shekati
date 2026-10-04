import Foundation
import SwiftData
import UIKit
import XCTest
import ShekatiCore
@testable import Shekati

@MainActor
final class ChequeLargeStoreTests: XCTestCase {
    func testThousandPhotoChequesReopenFilterTotalsManualOrderAndMeasuredMetadataFetch() throws {
        let count = 1_000
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shekati-LargeStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LargeStore.store")
        let front = try jpeg(side: "FRONT", color: .systemTeal)
        let back = try jpeg(side: "BACK", color: .systemIndigo)
        let fixtureStarted = Date()
        try autoreleasepool { try seedStore(url: storeURL, count: count, front: front, back: back) }
        let fixtureElapsed = Date().timeIntervalSince(fixtureStarted)

        // The seeding container/context have left scope. Reopen the on-disk store;
        // metadata access below never reads the external photo attributes.
        let container = try makeContainer(url: storeURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<ChequeRecord>())
        XCTAssertEqual(records.count, count)
        let snapshots = records.map(\.snapshot)
        let today = LocalDay(iso: "2026-10-04")!
        let filter = ChequeFilter(query: "DEMO BANK A", direction: .incoming, status: .pending,
                                 from: today.adding(days: 1), through: today.adding(days: 7), outstandingOnly: true)
        let expectedIndices = (0..<count).filter { index in
            let dayOffset = index % 31 - 15
            return index.isMultiple(of: 2) && index.isMultiple(of: 3) &&
                ![0, 1, 2].contains(index % 10) && (1...7).contains(dayOffset)
        }
        let expectedAmount = expectedIndices.reduce(Int64(0)) { $0 + Int64(1_001 + $1 * 37) }
        let filtered = ChequeListResult(cheques: snapshots, filter: filter, sort: .amount,
                                       ascending: false, today: today)
        XCTAssertEqual(filtered.cheques.map(\.number), expectedIndices.reversed().map { String(format: "%06d", $0) })
        XCTAssertEqual(filtered.totals.incomingMinorUnits, expectedAmount)
        XCTAssertEqual(filtered.totals.outgoingMinorUnits, 0)
        XCTAssertEqual(filtered.totals.incomingCount, expectedIndices.count)

        // Record XCTest's clock baseline separately from image rendering and writes.
        // A fresh context per iteration fetches metadata and computes the displayed
        // list; photos are decoded only in the explicit persistence checks below.
        var measuredResult: ChequeListResult?
        var measuredRecordCount = 0
        let measurementStarted = Date()
        measure(metrics: [XCTClockMetric()]) {
            do {
                let reader = ModelContext(container)
                reader.autosaveEnabled = false
                let loaded = try reader.fetch(FetchDescriptor<ChequeRecord>())
                measuredRecordCount = loaded.count
                measuredResult = ChequeListResult(cheques: loaded.map(\.snapshot), filter: filter,
                                                  sort: .amount, ascending: false, today: today)
            } catch { XCTFail("Metadata fetch failed: \(error.localizedDescription)") }
        }
        let measurementElapsed = Date().timeIntervalSince(measurementStarted)
        XCTAssertEqual(measuredRecordCount, count)
        XCTAssertEqual(measuredResult?.cheques.map(\.id), filtered.cheques.map(\.id))
        XCTAssertEqual(measuredResult?.totals.incomingMinorUnits, expectedAmount)

        let global = ChequeListEngine.filteredAndSorted(cheques: snapshots, filter: .init(),
                                                        sort: .manual, ascending: true, today: today).map(\.id)
        let visible = ChequeListResult(cheques: snapshots, filter: filter, sort: .manual,
                                      ascending: true, today: today).cheques.map(\.id)
        XCTAssertGreaterThan(visible.count, 1)
        let reordered = ChequeListEngine.reorderedIDs(all: global, visible: visible,
                                                       from: IndexSet(integer: 0), to: visible.count)
        let visibleSet = Set(visible)
        for index in global.indices where !visibleSet.contains(global[index]) {
            XCTAssertEqual(reordered[index], global[index])
        }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for (rank, id) in reordered.enumerated() where byID[id]?.manualRank != Int64(rank) {
            byID[id]?.manualRank = Int64(rank)
        }
        try context.save()
        let fresh = ModelContext(container)
        let saved = try fresh.fetch(FetchDescriptor<ChequeRecord>())
        let persistedOrder = ChequeListEngine.filteredAndSorted(cheques: saved.map(\.snapshot), filter: .init(),
                                                                sort: .manual, ascending: true, today: today).map(\.id)
        XCTAssertEqual(persistedOrder, reordered)
        for number in ["000000", "000999"] {
            let record = try XCTUnwrap(saved.first { $0.number == number })
            XCTAssertEqual(record.frontImageData, front)
            XCTAssertEqual(record.backImageData, back)
            let frontImage = try XCTUnwrap(UIImage(data: try XCTUnwrap(record.frontImageData)))
            let backImage = try XCTUnwrap(UIImage(data: try XCTUnwrap(record.backImageData)))
            XCTAssertEqual(frontImage.size, CGSize(width: 256, height: 256))
            XCTAssertEqual(backImage.size, CGSize(width: 256, height: 256))
        }
        let attachment = XCTAttachment(string: """
        On-disk SwiftData fixture: \(count) cheques; two valid 256 x 256 JPEGs per cheque.
        Front/back encoded bytes: \(front.count)/\(back.count).
        Fixture writes (outside measured interval): \(String(format: "%.3f", fixtureElapsed)) seconds.
        XCTest clock measurement total wall time: \(String(format: "%.3f", measurementElapsed)) seconds.
        The xcresult performance metrics contain the per-iteration metadata-fetch/list baseline.
        Filtered rows: \(expectedIndices.count); exact JOD minor-unit incoming total: \(expectedAmount).
        No timing threshold is asserted. Simulator baseline does not certify physical-device CPU, memory or battery.
        """
        )
        attachment.name = "1,000 photo cheques - store and metadata baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func seedStore(url: URL, count: Int, front: Data, back: Data) throws {
        let container = try makeContainer(url: url)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let today = LocalDay(iso: "2026-10-04")!
        for index in 0..<count {
            let status: ChequeStatus
            switch index % 10 {
            case 0: status = .settled
            case 1: status = .cancelled
            case 2: status = .returned
            default: status = .pending
            }
            let snapshot = ChequeSnapshot(direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                                           status: status, amountMinorUnits: Int64(1_001 + index * 37), currencyCode: "JOD",
                                           dueDate: today.adding(days: index % 31 - 15),
                                           actualDate: status == .settled ? today : nil,
                                           number: String(format: "%06d", index),
                                           bank: index.isMultiple(of: 3) ? "Demo Bank A" : "Demo Bank B",
                                           party: "Demo party \(index)", createdAt: Date(timeIntervalSince1970: 1_000 + Double(index)),
                                           manualRank: Int64(index))
            writer.insert(ChequeRecord(snapshot: snapshot, frontImageData: front, backImageData: back, remindersEnabled: false))
        }
        try writer.save()
    }

    private func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([ChequeRecord.self, AppConfiguration.self])
        let configuration = ModelConfiguration("LargeStoreTests", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func jpeg(side: String, color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            color.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 16, y: 36, width: 224, height: 184))
            ("DEMO CHEQUE\n\(side)\n000123" as NSString).draw(in: CGRect(x: 28, y: 58, width: 200, height: 130),
                                                             withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.85))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        return data
    }
}
