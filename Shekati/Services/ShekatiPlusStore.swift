import Foundation
import StoreKit
import SwiftUI

@MainActor
final class ShekatiPlusStore: ObservableObject {
    static let monthlyID = "com.mf103871.shekati.plus.monthly"
    static let annualID = "com.mf103871.shekati.plus.annual"
    static let productIDs: Set<String> = [monthlyID, annualID]

    @Published private(set) var isPlus = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isBusy = false
    @Published private(set) var notice: String?
    private var listener: Task<Void, Never>?
    private var refreshNumber = 0

    init() {
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, case .verified(let transaction) = result,
                      Self.productIDs.contains(transaction.productID) else { continue }
                await self.refreshEntitlement()
                await transaction.finish()
            }
        }
    }

    deinit { listener?.cancel() }

    func refreshEntitlement() async {
        refreshNumber += 1
        let request = refreshNumber
        var entitled = false
        // StoreKit's signed current entitlements include eligible billing-grace periods.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            entitled = true
        }
        if request == refreshNumber { isPlus = entitled }
    }

    func loadProducts() async {
        await refreshEntitlement()
        do {
            let response = try await Product.products(for: Self.productIDs)
            products = response.sorted { $0.id < $1.id }
            if response.count != Self.productIDs.count {
                notice = "Some purchase options are unavailable. Please try again later."
            } else { notice = nil }
        } catch {
            notice = "Could not load subscription prices. Please try again."
        }
    }

    func purchase(_ product: Product) async {
        guard !isBusy, Self.productIDs.contains(product.id) else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refreshEntitlement()
                await transaction.finish()
            case .success(.unverified(_, _)):
                notice = "Apple could not verify this purchase."
            case .pending:
                notice = "The purchase is awaiting approval."
            case .userCancelled: break
            @unknown default:
                notice = "Please check your subscription status."
            }
        } catch {
            notice = "The purchase could not be completed. Please try again."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            notice = isPlus ? "Your subscription is active." : "No active subscription was found."
        } catch {
            notice = "Could not restore purchases. Please try again."
        }
    }
}

