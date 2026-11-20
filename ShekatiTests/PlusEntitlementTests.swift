import StoreKit
import StoreKitTest
import XCTest
@testable import Shekati

@MainActor
final class PlusEntitlementTests: XCTestCase {
    private func expectEntitlement(_ expected: Bool, store: ShekatiPlusStore, product: String,
                                   file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        repeat {
            await store.refreshEntitlement()
            if store.isPlus == expected { return }
            try await Task.sleep(for: .milliseconds(200))
        } while ContinuousClock.now < deadline
        let latest = await StoreKit.Transaction.latest(for: product)
        let diagnostic: String
        switch latest {
        case .verified(let transaction):
            diagnostic = "verified, expiration=\(String(describing: transaction.expirationDate)), revoked=\(transaction.revocationDate != nil)"
        case .unverified(_, let error):
            diagnostic = "unverified: \(error.localizedDescription)"
        case nil:
            diagnostic = "no transaction visible to the app"
        }
        XCTFail("Expected Plus=\(expected), received \(store.isPlus); \(diagnostic)", file: file, line: line)
    }

    func testAppleTransactionsGrantAndRemoveAccess() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ShekatiPlus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let store = ShekatiPlusStore()
        await store.loadProducts()
        XCTAssertEqual(Set(store.products.map(\.id)), ShekatiPlusStore.productIDs)
        XCTAssertFalse(store.isPlus)
        _ = try await session.buyProduct(identifier: ShekatiPlusStore.monthlyID)
        try await expectEntitlement(true, store: store, product: ShekatiPlusStore.monthlyID)
        let transactionsBeforeRenewal = session.allTransactions().count
        try session.forceRenewalOfSubscription(productIdentifier: ShekatiPlusStore.monthlyID)
        XCTAssertGreaterThan(session.allTransactions().count, transactionsBeforeRenewal)
        let reopened = ShekatiPlusStore()
        try await expectEntitlement(true, store: reopened, product: ShekatiPlusStore.monthlyID)
        await reopened.restore()
        XCTAssertTrue(reopened.isPlus)
        XCTAssertEqual(reopened.notice, "Your subscription is active.")
        try session.expireSubscription(productIdentifier: ShekatiPlusStore.monthlyID)
        try await expectEntitlement(false, store: store, product: ShekatiPlusStore.monthlyID)
        _ = try await session.buyProduct(identifier: ShekatiPlusStore.annualID)
        try await expectEntitlement(true, store: store, product: ShekatiPlusStore.annualID)
        let purchase = try XCTUnwrap(session.allTransactions().last(where: { $0.productIdentifier == ShekatiPlusStore.annualID }))
        try session.refundTransaction(identifier: purchase.identifier)
        try await expectEntitlement(false, store: store, product: ShekatiPlusStore.annualID)
    }
}

