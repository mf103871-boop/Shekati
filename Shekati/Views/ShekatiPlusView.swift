import StoreKit
import SwiftUI

struct ShekatiPlusView: View {
    @EnvironmentObject private var plus: ShekatiPlusStore
    @Environment(AppState.self) private var app
    @State private var managing = false

    var body: some View {
        List {
            Section {
                Label(app.tr("Shekati Plus"), systemImage: "checkmark.seal.fill")
                    .font(.title2.bold()).foregroundStyle(Theme.accent)
                Text(app.tr("Track unlimited active cheques across your bank accounts."))
                Label(app.tr("Scan and review cheque details"), systemImage: "document.viewfinder")
                Label(app.tr("Endorsements, partial settlements and replacements"), systemImage: "arrow.left.arrow.right")
                Label(app.tr("Cash flow forecasts and advanced reports"), systemImage: "chart.bar")
            }
            if plus.isPlus {
                Section { Label(app.tr("Your subscription is active."), systemImage: "checkmark.circle") }
            } else {
                Section {
                    ForEach(plus.products) { product in
                        Button {
                            Task { await plus.purchase(product) }
                        } label: {
                            HStack {
                                Text(app.tr(product.id == ShekatiPlusStore.annualID ? "Annual subscription" : "Monthly subscription"))
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.headline).foregroundStyle(.primary)
                            }
                        }
                        .disabled(plus.isBusy)
                        .accessibilityIdentifier(product.id)
                    }
                    if plus.products.isEmpty {
                        Button(app.tr("Reload prices")) { Task { await plus.loadProducts() } }
                    }
                } header: { Text(app.tr("Choose a subscription")) }
                  footer: { Text(app.tr("Charged at purchase. Renews automatically until cancelled in your Apple Account.")) }
            }
            Section {
                Button(app.tr("Restore purchases")) { Task { await plus.restore() } }.disabled(plus.isBusy)
                Button(app.tr("Manage subscription")) { managing = true }
                if plus.isBusy { ProgressView() }
                if let notice = plus.notice { Text(app.tr(notice)).font(.footnote) }
            }
            Section {
                Link(app.tr("Terms of use"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link(app.tr("Privacy policy"), destination: URL(string: "https://mf103871-boop.github.io/Shekati/privacy.html")!)
            } footer: {
                Text(app.tr("Free includes one account and ten active cheques. Your records remain available to read, close and export."))
            }
        }
        .navigationTitle(app.tr("Shekati Plus"))
        .task { await plus.loadProducts() }
        .manageSubscriptionsSheet(isPresented: $managing)
    }
}

