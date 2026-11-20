import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @EnvironmentObject private var plus: ShekatiPlusStore
    @Query(filter: #Predicate<ChequeRecord> { $0.deletedAt == nil }) private var records: [ChequeRecord]
    @Query(sort: \BankAccountRecord.name) private var accounts: [BankAccountRecord]
    @Query private var events: [LedgerEventRecord]
    @AppStorage("shekati.dashboardAccount") private var selectedID = ""
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var showingEditor = false

    private var account: BankAccountRecord? {
        accounts.first { $0.id.uuidString == selectedID } ?? accounts.first
    }

    private var upcoming: [ChequeRecord] {
        records.filter { record in
            record.bankAccountID == account?.id && BankingLedger.position(for: record, events: events).isOpen
        }.sorted { ($0.dueDateISO, $0.number) < ($1.dueDateISO, $1.number) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let account {
                    Menu {
                        ForEach(accounts) { item in
                            Button { selectedID = item.id.uuidString } label: {
                                Label(item.name + " · " + item.currencyCode,
                                      systemImage: item.id == account.id ? "checkmark" : "building.columns")
                            }
                        }
                    } label: {
                        HStack {
                            Label(account.name + " · " + account.currencyCode, systemImage: "building.columns")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityLabel(app.tr("Bank account") + ", " + account.name)
                    AccountLiquidityView(account: account, isPlus: plus.isPlus, hidesAmounts: hidesAmounts)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(app.tr("Add your first bank account"), systemImage: "building.columns").font(.headline)
                        Text(app.tr("Enter the opening balance to see your available balance and upcoming commitments.")).font(.subheadline)
                        NavigationLink(app.tr("Bank accounts")) { BankingAccountsView(isPlus: plus.isPlus) }
                            .buttonStyle(.borderedProminent)
                    }.shekatiCard()
                }
                HStack {
                    Text(app.tr("Next cheques")).font(.headline)
                    Spacer()
                    NavigationLink(app.tr("See all")) { ChequeListView() }
                }
                ForEach(upcoming.prefix(4)) { record in
                    NavigationLink { ChequeDetailView(record: record) } label: {
                        ChequeRowView(record: record).padding(.horizontal, 14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
                if upcoming.isEmpty {
                    Text(app.tr("No outstanding cheques")).foregroundStyle(.secondary)
                }
                if let account, records.contains(where: { $0.bankAccountID == nil }) {
                    NavigationLink { UnlinkedChequeView(currency: account.currencyCode) } label: {
                        Label(app.tr("Review cheques without an account"), systemImage: "link.badge.plus")
                    }
                }
                Button { showingEditor = true } label: {
                    Label(app.tr("Add cheque"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("addCheque")
                if let error = app.persistenceMessage { Text(error).foregroundStyle(Theme.red) }
                if app.notifications.isDenied {
                    NavigationLink(app.tr("Notifications are off")) { SettingsView() }
                } else if let day = app.notifications.firstUncoveredDate {
                    NavigationLink { SettingsView() } label: {
                        Label(app.tr("Refresh upcoming reminders") + " · " + app.formatDay(LocalDay(date: day)), systemImage: "bell")
                    }
                }
            }.padding(16)
        }.background(Theme.background).navigationTitle(app.tr("Shekati"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AmountPrivacyButton() } }
            .sheet(isPresented: $showingEditor) { NavigationStack { ChequeEditorView() } }
    }
}

@MainActor
private struct UnlinkedChequeView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    let currency: String
    var body: some View {
        List(records.filter { $0.deletedAt == nil && $0.bankAccountID == nil && $0.currencyCode == currency }) { record in
            NavigationLink { ChequeDetailView(record: record) } label: { ChequeRowView(record: record) }
        }.navigationTitle(app.tr("Review cheques without an account"))
    }
}
