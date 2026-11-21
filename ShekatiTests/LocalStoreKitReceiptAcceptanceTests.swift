import CryptoKit
import StoreKit
import StoreKitTest
import XCTest
@testable import Shekati

@MainActor
final class LocalStoreKitReceiptAcceptanceTests: XCTestCase {
    private enum ReceiptError: Error { case unverifiedLocalTransaction }

    private func startLocalSession() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ShekatiPlus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func receipt(for productID: String) async throws -> (transaction: StoreKit.Transaction, digest: String) {
        let result = await StoreKit.Transaction.latest(for: productID)
        let verified = try XCTUnwrap(result)
        guard case .verified(let transaction) = verified else {
            throw ReceiptError.unverifiedLocalTransaction
        }
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertEqual(transaction.productID, productID)
        XCTAssertNil(transaction.revocationDate)
        let data = Data(verified.jwsRepresentation.utf8)
        XCTAssertFalse(data.isEmpty)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (transaction, digest)
    }

    private func attach(_ text: String, as name: String) {
        let evidence = XCTAttachment(string: text)
        evidence.name = name
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testMonthlyPurchaseThroughAppProducesLocalVerifiedTransaction() async throws {
        let session = try startLocalSession()
        defer { session.clearTransactions() }
        let store = ShekatiPlusStore()
        await store.loadProducts()
        let product = try XCTUnwrap(store.products.first { $0.id == ShekatiPlusStore.monthlyID })
        XCTAssertFalse(store.isPlus)
        await store.purchase(product)
        XCTAssertTrue(store.isPlus)
        let result = try await receipt(for: product.id)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == product.id }.count, 1)
        attach("Product: \(product.id)\nEnvironment: Xcode\nApplication purchase granted Plus: \(store.isPlus)\nVerified JWS SHA-256: \(result.digest)", as: "Local-monthly-purchase")
    }

    func testAnnualRestorationThroughAppRecoversExistingLocalVerifiedTransaction() async throws {
        let session = try startLocalSession()
        defer { session.clearTransactions() }
        let productID = ShekatiPlusStore.annualID
        _ = try await session.buyProduct(identifier: productID)
        let prior = try await receipt(for: productID)
        let countBefore = session.allTransactions().count
        let reopened = ShekatiPlusStore()
        XCTAssertFalse(reopened.isPlus)
        await reopened.restore()
        XCTAssertTrue(reopened.isPlus)
        XCTAssertEqual(reopened.notice, "Your subscription is active.")
        let restored = try await receipt(for: productID)
        XCTAssertEqual(restored.transaction.originalID, prior.transaction.originalID)
        XCTAssertEqual(restored.transaction.id, prior.transaction.id)
        XCTAssertEqual(session.allTransactions().count, countBefore)
        attach("Product: \(productID)\nEnvironment: Xcode\nApplication restore granted Plus: \(reopened.isPlus)\nRestore notice: \(reopened.notice ?? "")\nMatching original transaction and transaction ID: \(prior.transaction.id == restored.transaction.id && prior.transaction.originalID == restored.transaction.originalID)\nTransactions before/after: \(countBefore)/\(session.allTransactions().count)\nEarlier verified JWS SHA-256: \(prior.digest)\nRestored verified JWS SHA-256: \(restored.digest)", as: "Local-annual-restore")
    }
}
