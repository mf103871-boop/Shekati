import Charts
import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @EnvironmentObject private var plus: ShekatiPlusStore
    @Query private var records: [ChequeRecord]
    @Query(sort: \BankAccountRecord.name) private var accounts: [BankAccountRecord]
    @Query private var events: [LedgerEventRecord]
    @AppStorage("shekati.dashboardAccount") private var selectedID = ""
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var showingEditor = false

    private var account: BankAccountRecord? {
        accounts.first { $0.id.uuidString == selectedID } ?? accounts.first
    }

    private func upcoming(_ audit: ChequeAudit) -> [ChequeRecord] {
        records.filter { record in
            guard record.isActive, record.bankAccountID == account?.id, !audit.disputed.contains(record.id), let position = audit.positions[record.id] else { return false }
            return position.isOpen && position.state != .draft && position.state != .endorsed
        }.sorted { ($0.dueDateISO, $0.number) < ($1.dueDateISO, $1.number) }
    }

    var body: some View {
        let audit = ChequeAudit(records: records, events: events)
        let upcoming = self.upcoming(audit)
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
                    if plus.isPlus, !hidesAmounts,
                       let outlook = try? BankingLedger.outlook(account: account, records: records, events: events,
                                                                today: app.today, horizon: 30) {
                        let divisor = pow(10.0, Double(CurrencyMath.fractionDigits(for: account.currencyCode)))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(app.tr("Shekati Plus")).font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(app.tr("Cash forecast") + " · " + app.tr("30 days")).font(.headline)
                            Chart {
                                RuleMark(y: .value(account.currencyCode, 0))
                                    .lineStyle(StrokeStyle(dash: [3, 3])).foregroundStyle(.secondary)
                                ForEach(outlook.points) { point in
                                    LineMark(x: .value(app.tr("Date"), point.day.date()),
                                             y: .value(account.currencyCode, Double(point.balance) / divisor))
                                        .interpolationMethod(.stepEnd).foregroundStyle(Theme.accent)
                                }
                            }
                            .chartYAxisLabel(account.currencyCode)
                            .chartXAxis {
                                AxisMarks(values: [app.today.date(), app.today.adding(days: 15).date(), app.today.adding(days: 30).date()]) {
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .frame(height: 115)
                            .accessibilityLabel(app.tr("Cash forecast") + " · " + account.currencyCode)
                        }.shekatiCard()
                    }
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
                        ChequeRowView(record: record, position: audit.positions[record.id]).padding(.horizontal, 14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
                if upcoming.isEmpty {
                    Text(app.tr("No outstanding cheques")).foregroundStyle(.secondary)
                }
                if let account, records.contains(where: { $0.isActive && $0.bankAccountID == nil }) {
                    NavigationLink { UnlinkedChequeView(currency: account.currencyCode) } label: {
                        Label(app.tr("Review cheques without an account"), systemImage: "link.badge.plus")
                    }
                }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingEditor = true } label: { Label(app.tr("Add cheque"), systemImage: "plus") }
                        .accessibilityIdentifier("addCheque")
                }
                ToolbarItem(placement: .topBarTrailing) { AmountPrivacyButton() }
            }
            .sheet(isPresented: $showingEditor) { ChequeEditorSheet() }
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
