import StoreKitTest
import XCTest
@testable import Shekati

@MainActor
final class PlusEntitlementTests: XCTestCase {
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
        await store.refreshEntitlement()
        XCTAssertTrue(store.isPlus)
        try session.expireSubscription(productIdentifier: ShekatiPlusStore.monthlyID)
        await store.refreshEntitlement()
        XCTAssertFalse(store.isPlus)
        _ = try await session.buyProduct(identifier: ShekatiPlusStore.annualID)
        await store.refreshEntitlement()
        XCTAssertTrue(store.isPlus)
        let purchase = try XCTUnwrap(session.allTransactions().last(where: { $0.productIdentifier == ShekatiPlusStore.annualID }))
        try session.refundTransaction(identifier: purchase.identifier)
        await store.refreshEntitlement()
        XCTAssertFalse(store.isPlus)
    }
}

