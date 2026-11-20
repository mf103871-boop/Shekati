import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct CurrencySetupView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \AppConfiguration.createdAt) private var configurations: [AppConfiguration]
    @State private var showingCurrencies = false
    @State private var accountName = ""
    @State private var openingBalance = "0"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack { BrandMark(); Spacer(); languagePicker }
                    Text(app.tr("Your cheques.\nClearly organised."))
                        .font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text(app.tr("Track what you owe and what you will collect, with timely reminders and everything in one place."))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 20) {
                        feature("calendar", "Know what is due")
                        feature("camera.viewfinder", "Scan, review, save")
                        feature("icloud", "Your records, with you")
                    }.shekatiCard()
                    VStack(alignment: .leading, spacing: 12) {
                        Text(app.tr("Your first bank account")).font(.headline)
                        TextField(app.tr("Current account"), text: $accountName)
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("openingAccountName")
                        LabeledContent(app.tr("Opening balance")) {
                            TextField("0", text: $openingBalance)
                                .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("openingAccountBalance")
                        }
                    }.shekatiCard()
                    Text(app.tr("Choose the currency for this account and its first chequebook."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { showingCurrencies = true } label: {
                        HStack { Text(app.tr("Choose currency")); Spacer(); Image(systemName: "arrow.forward") }
                            .foregroundStyle(Theme.onAccent)
                            .padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("chooseCurrency")
                    if let message = app.persistenceMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }.padding(28)
            }.background(Theme.background)
                .sheet(isPresented: $showingCurrencies) {
                    NavigationStack { CurrencyPickerView(initialAccountName: accountName.isEmpty ? app.tr("Current account") : accountName, openingBalance: openingBalance) }
                }
        }
    }

    private var languagePicker: some View {
        Menu {
            ForEach(AppLanguage.allCases) { choice in
                Button(choice.displayName) { app.preferences.language = choice }
            }
        } label: {
            Label(app.preferences.language.displayName, systemImage: "globe")
                .font(.subheadline)
        }
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        Label { Text(app.tr(title)).font(.subheadline.weight(.medium)) } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 30)
        }
    }
}

@MainActor
struct CurrencyPickerView: View {
    var initialAccountName: String? = nil
    var openingBalance = "0"
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ChequeRecord]
    @Query(sort: \AppConfiguration.createdAt) private var configurations: [AppConfiguration]
    @State private var query = ""
    @State private var errorMessage: String?
    private let frequent = ["USD", "JOD", "EUR", "SAR", "AED", "KWD", "ILS", "GBP", "EGP", "IQD", "JPY"]
    private var currencies: [String] {
        let all = Locale.commonISOCurrencyCodes.sorted()
        let ordered = frequent + all.filter { !frequent.contains($0) }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ordered }
        return ordered.filter { $0.localizedCaseInsensitiveContains(query) || name($0).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                ForEach(currencies, id: \.self) { code in
                    Button {
                        save(code)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name(code)).foregroundStyle(.primary)
                                Text(code).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.currencyCode == code { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                        }.padding(.vertical, 3)
                    }
                        .accessibilityIdentifier("currency_\(code)")
                }
            } footer: {
                Text(app.tr("This default applies to new records. Existing amounts retain their currency."))
            }
        }.navigationTitle(app.tr("Currency"))
            .searchable(text: $query.westernDigits, prompt: app.tr("Search currencies"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { dismiss() } } }
            .alert(app.tr("Could not save changes."), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button(app.tr("OK"), role: .cancel) {}
                } message: { Text(errorMessage ?? "") }
    }
    private func name(_ code: String) -> String { app.preferences.language.locale.localizedString(forCurrencyCode: code) ?? code }
    private func save(_ code: String) {
        guard Locale.commonISOCurrencyCodes.contains(code) else { return }
        if let name = initialAccountName {
            do {
                if try context.fetchCount(FetchDescriptor<BankAccountRecord>()) == 0 {
                    guard let minor = BankingLedger.signedAmount(openingBalance, currency: code),
                          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        errorMessage = app.tr("Check the account name and opening balance.")
                        return
                    }
                    let account = BankAccountRecord(name: name, currencyCode: code, openingMinor: minor)
                    context.insert(account)
                    context.insert(ChequeBookRecord(accountID: account.id, name: name))
                }
            } catch {
                errorMessage = app.tr("Could not save changes.")
                return
            }
        }
        if let configuration = configurations.first { configuration.currencyCode = code }
        else { context.insert(AppConfiguration(currencyCode: code)) }
        do {
            try context.save()
            app.currencyCode = code
            app.persistenceMessage = nil
            app.didMutate()
            dismiss()
        } catch { context.rollback(); errorMessage = app.tr("Your change was not saved. Please try again.") }
    }
}
