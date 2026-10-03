import Foundation
import XCTest
import CloudKit
import CoreData
@testable import Shekati

@MainActor
final class SyncMonitorTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_000_100)

    private func monitor() -> SyncMonitor {
        SyncMonitor(observeChanges: false, accountStatusProvider: { .available })
    }

    private func complete(_ monitor: SyncMonitor, _ type: NSPersistentCloudKitContainer.EventType,
                          at date: Date, succeeded: Bool, detail: String? = nil) {
        monitor.receiveEvent(type: type, identifier: UUID(), endDate: date,
                             succeeded: succeeded, errorDescription: detail)
    }

    func testAccountRefreshDoesNotMaskLaterTransferFailureWithOldSuccess() async {
        let sync = monitor()
        complete(sync, .export, at: earlier, succeeded: true)
        complete(sync, .export, at: later, succeeded: false, detail: "Export rejected")

        await sync.refresh()
        await sync.refresh() // Settings/foreground checks can occur repeatedly.

        XCTAssertEqual(sync.state, .failed)
        XCTAssertEqual(sync.detail, "Export rejected")
        XCTAssertEqual(sync.lastSyncDate, earlier)
    }

    func testOfflineAndNetworkRestorationPreserveTransferFailure() async {
        let sync = monitor()
        complete(sync, .import, at: earlier, succeeded: true)
        complete(sync, .import, at: later, succeeded: false, detail: "Import rejected")

        await sync.updateNetworkAvailability(false)
        XCTAssertEqual(sync.state, .offline)
        XCTAssertEqual(sync.detail, "Import rejected")
        await sync.updateNetworkAvailability(true)

        XCTAssertEqual(sync.state, .failed)
        XCTAssertEqual(sync.detail, "Import rejected")
        XCTAssertEqual(sync.lastSyncDate, earlier)
    }

    func testSetupSuccessDoesNotClearFailedDataTransfer() async {
        let sync = monitor()
        complete(sync, .export, at: earlier, succeeded: false, detail: "Data export rejected")
        complete(sync, .setup, at: later, succeeded: true)
        await sync.refresh()

        XCTAssertEqual(sync.state, .failed)
        XCTAssertEqual(sync.detail, "Data export rejected")
        XCTAssertNil(sync.lastSyncDate)
    }

    func testNewSuccessfulMatchingTransferEstablishesRecovery() async {
        let sync = monitor()
        complete(sync, .export, at: earlier, succeeded: false, detail: "Export rejected")
        await sync.refresh()
        complete(sync, .export, at: later, succeeded: true)

        XCTAssertEqual(sync.state, .synced)
        XCTAssertEqual(sync.lastSyncDate, later)
        XCTAssertNil(sync.detail)
    }

    func testOlderOrDifferentTransferSuccessDoesNotEraseUnresolvedFailure() async {
        let sync = monitor()
        complete(sync, .export, at: later, succeeded: false, detail: "Export rejected")
        complete(sync, .export, at: earlier, succeeded: true) // Delayed event delivery.
        complete(sync, .import, at: later.addingTimeInterval(10), succeeded: true)
        await sync.refresh()

        XCTAssertEqual(sync.state, .failed)
        XCTAssertEqual(sync.detail, "Export rejected")
        XCTAssertEqual(sync.lastSyncDate, later.addingTimeInterval(10))
    }

    func testAccountCheckErrorClearsAfterSuccessfulAccountCheck() async {
        var failAccountCheck = true
        let sync = SyncMonitor(observeChanges: false, accountStatusProvider: {
            if failAccountCheck { throw NSError(domain: "SyncMonitorTests", code: 1) }
            return .available
        })
        await sync.refresh()
        XCTAssertEqual(sync.state, .failed)
        XCTAssertNotNil(sync.detail)

        failAccountCheck = false
        await sync.refresh()

        XCTAssertEqual(sync.state, .available)
        XCTAssertNil(sync.detail)
        XCTAssertNil(sync.lastSyncDate)
    }

    func testActiveTransferRemainsSyncingThroughRefreshAndReconnect() async {
        let sync = monitor()
        let eventID = UUID()
        sync.receiveEvent(type: .import, identifier: eventID, endDate: nil, succeeded: false)
        await sync.refresh()
        XCTAssertEqual(sync.state, .syncing)
        await sync.updateNetworkAvailability(false)
        XCTAssertEqual(sync.state, .offline)
        await sync.updateNetworkAvailability(true)
        XCTAssertEqual(sync.state, .syncing)

        sync.receiveEvent(type: .import, identifier: eventID, endDate: later, succeeded: true)
        XCTAssertEqual(sync.state, .synced)
    }

    func testUnavailableAndLocalOnlyStatesDoNotClaimSyncRecovery() async {
        var accountStatus: CKAccountStatus = .noAccount
        let sync = SyncMonitor(observeChanges: false, accountStatusProvider: { accountStatus })
        complete(sync, .export, at: earlier, succeeded: false, detail: "Export rejected")
        await sync.refresh()
        XCTAssertEqual(sync.state, .unavailable)
        accountStatus = .available
        await sync.refresh()
        XCTAssertEqual(sync.state, .failed)
        XCTAssertEqual(sync.detail, "Export rejected")

        var accountCheckCount = 0
        let local = SyncMonitor(localOnlyReason: "Test local store", observeChanges: false,
                                accountStatusProvider: { accountCheckCount += 1; return .available })
        complete(local, .export, at: later, succeeded: true)
        await local.updateNetworkAvailability(false)
        await local.refresh()
        XCTAssertEqual(local.state, .localOnly)
        XCTAssertEqual(local.detail, "Test local store")
        XCTAssertNil(local.lastSyncDate)
        XCTAssertEqual(accountCheckCount, 0)
    }
}
