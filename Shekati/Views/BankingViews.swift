import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import ShekatiCore

@MainActor
struct BankingAccountsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \BankAccountRecord.createdAt) private var accounts: [BankAccountRecord]
    @Query private var books: [ChequeBookRecord]
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var adding = false
    @State private var showingPlus = false
    let isPlus: Bool

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    BankingAccountDetail(account: account, isPlus: isPlus, hidesAmounts: hidesAmounts)
                } label: {
                    VStack(alignment: .leading) {
                        Text(account.name)
                        Text(account.currencyCode).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                if isPlus || accounts.isEmpty { adding = true } else { showingPlus = true }
            } label: { Label(app.tr("Add bank account"), systemImage: "plus.circle") }
        }
        .navigationTitle(app.tr("Bank accounts"))
        .sheet(isPresented: $adding) { AccountCreationView(isPlus: isPlus) }
        .sheet(isPresented: $showingPlus) { ShekatiPlusView() }
    }
}

@MainActor
private struct AccountCreationView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency = ""
    @State private var opening = "0"
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var error: String?
    let isPlus: Bool
    var body: some View {
        NavigationStack {
            Form {
                TextField(app.tr("Account name"), text: $name)
                Picker(app.tr("Currency"), selection: $currency) {
                    ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                }
                if hidesAmounts {
                    SecureField(app.tr("Opening balance"), text: $opening).keyboardType(.numbersAndPunctuation)
                } else {
                    TextField(app.tr("Opening balance"), text: $opening).keyboardType(.numbersAndPunctuation)
                }
                if let error { Text(app.tr(error)).foregroundStyle(.red) }
                Button(app.tr("Save")) {
                    do {
                        guard let amount = BankingLedger.signedAmount(opening, currency: currency) else { throw BankingError.invalid }
                        try BankingLedger.addAccount(name: name, currency: currency, opening: amount, isPlus: isPlus, context: context)
                        app.didMutate(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle(app.tr("Add bank account"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { dismiss() } } }
            .onAppear { if currency.isEmpty { currency = app.currencyCode.isEmpty ? "USD" : app.currencyCode } }
        }
    }
}

@MainActor
private struct BankingAccountDetail: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var books: [ChequeBookRecord]
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    @State private var bookName = ""
    @State private var statement = ""
    @State private var reconciliationNote = ""
    @State private var review: ReconciliationReview?
    @State private var discarded: LedgerOperation?
    @State private var reason = ""
    @State private var error: String?
    let account: BankAccountRecord
    let isPlus: Bool
    let hidesAmounts: Bool

    private struct ReconciliationReview: Identifiable {
        let id = UUID()
        let balance: Int64
        let statement: Int64
        let difference: Int64
    }

    var body: some View {
        Form {
            AccountLiquidityView(account: account, isPlus: isPlus, hidesAmounts: hidesAmounts)
            Section(app.tr("Cheque books")) {
                ForEach(books.filter { $0.accountID == account.id }) { Text($0.name) }
                TextField(app.tr("Cheque book name"), text: $bookName)
                Button(app.tr("Add cheque book")) {
                    let clean = bookName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    context.insert(ChequeBookRecord(accountID: account.id, name: clean))
                    do { try BankingLedger.save(context); bookName = ""; app.didMutate() }
                    catch { self.error = error.localizedDescription }
                }.disabled(bookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section(app.tr("Reconcile account")) {
                ForEach(BankingLedger.reconciliationConflicts(account: account, events: events)) { entry in
                    Button {
                        discarded = entry; reason = ""
                    } label: {
                        let value = hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: entry.amount, currencyCode: account.currencyCode, locale: app.preferences.language.locale)
                        Text(app.tr("Review conflicting entries") + " · " + app.formatDay(entry.day) + " · " + value)
                    }
                }
                if hidesAmounts {
                    SecureField(app.tr("Statement balance"), text: $statement).keyboardType(.numbersAndPunctuation)
                } else {
                    TextField(app.tr("Statement balance"), text: $statement).keyboardType(.numbersAndPunctuation)
                }
                TextField(app.tr("Reason"), text: $reconciliationNote)
                Button(app.tr("Review difference")) {
                    do {
                        guard let target = BankingLedger.signedAmount(statement, currency: account.currencyCode) else { throw BankingError.invalid }
                        let expected = try BankingLedger.outlook(account: account, records: records, events: events, today: app.today).recorded
                        let delta = target.subtractingReportingOverflow(expected)
                        guard !delta.overflow else { throw BankingError.invalid }
                        review = ReconciliationReview(balance: expected, statement: target, difference: delta.partialValue)
                    } catch { self.error = error.localizedDescription }
                }
            }
            if let checkpoints = try? BankingLedger.adjustments(account: account, events: events), !checkpoints.isEmpty {
                Section(app.tr("Activity history")) {
                    ForEach(Array(checkpoints.reversed())) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            let amount = hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: entry.amount, currencyCode: account.currencyCode, locale: app.preferences.language.locale)
                            LabeledContent(app.formatDay(entry.day), value: amount)
                            if !entry.party.isEmpty { Text(entry.party).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let error { Text(app.tr(error)).foregroundStyle(.red) }
        }
        .navigationTitle(account.name)
        .sheet(item: $discarded) { operation in
            NavigationStack {
                Form {
                    TextField(app.tr("Reason"), text: $reason)
                    Button(app.tr("Dismiss conflicting entry"), role: .destructive) {
                        do {
                            try BankingLedger.discardAdjustment(operation, reason: reason, account: account, context: context)
                            app.didMutate(); error = nil
                        } catch { self.error = error.localizedDescription }
                        discarded = nil
                    }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.navigationTitle(app.tr("Review conflicting entries"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { discarded = nil } } }
            }
        }
        .sheet(item: $review) { item in
            NavigationStack {
                Form {
                    let code = account.currencyCode
                    ForEach([("Recorded balance", item.balance), ("Statement balance", item.statement), ("Adjustment", item.difference)], id: \.0) { label, value in
                        LabeledContent(app.tr(label), value: hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: value, currencyCode: code, locale: app.preferences.language.locale))
                    }
                    LabeledContent(app.tr("Date"), value: app.formatDay(app.today))
                    if !reconciliationNote.isEmpty { LabeledContent(app.tr("Reason"), value: reconciliationNote) }
                    Button(app.tr("Confirm reconciliation")) {
                        do {
                            try BankingLedger.reconcile(account, statement: item.statement, expected: item.balance, reason: reconciliationNote, context: context)
                            app.didMutate(); statement = ""; reconciliationNote = ""; error = nil
                        } catch { self.error = error.localizedDescription }
                        review = nil
                    }
                }.navigationTitle(app.tr("Review difference"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { review = nil } } }
            }
        }
    }
}

@MainActor
struct AccountLiquidityView: View {
    @Environment(\.colorScheme) private var colorScheme
    let account: BankAccountRecord
    let isPlus: Bool
    var hidesAmounts = false
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    @State private var showingPlus = false
    private func money(_ n: Int64) -> String {
        hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: n, currencyCode: account.currencyCode, locale: app.preferences.language.locale)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let outlook = try? BankingLedger.outlook(account: account, records: records, events: events, today: app.today) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(app.tr("Estimated available in 7 days")).font(.subheadline)
                    ReadableCurrencyAmount(minorUnits: outlook.available7, currencyCode: account.currencyCode,
                                           formatted: money(outlook.available7))
                        .font(.largeTitle.bold())
                    Divider().overlay(.white.opacity(0.5))
                    ResponsiveValueRow(title: app.tr("Recorded balance"), value: money(outlook.recorded),
                                       stackedTitleStyle: AnyShapeStyle(.white))
                    ResponsiveValueRow(title: app.tr("Outgoing due within 7 days"), value: money(outlook.outgoing7),
                                       stackedTitleStyle: AnyShapeStyle(.white))
                        .accessibilityIdentifier("outgoingDueAmount")
                    if let reconciled = try? BankingLedger.adjustments(account: account, events: events).last?.day {
                        Text(app.tr("Last reconciliation") + " · " + app.formatDay(reconciled)).font(.caption)
                    } else {
                        Text(app.tr("Opening balance") + " · " + app.formatDay(LocalDay(date: account.createdAt))).font(.caption)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.06, green: 0.30, blue: 0.32), in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.white)
                ResponsiveValueRow(title: app.tr("Expected incoming in 7 days"), value: money(outlook.incoming7))
                if isPlus {
                    NavigationLink {
                        LiquidityForecast(account: account, focusDay: outlook.points.first(where: { $0.balance < 0 })?.day,
                                          today: app.today)
                    } label: {
                        if let deficit = outlook.points.first(where: { $0.balance < 0 }) {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.tr("Expected shortfall")).font(.subheadline.weight(.semibold))
                                    Text(app.formatDay(deficit.day) + " · " + money(deficit.balance))
                                        .font(.footnote).monospacedDigit()
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").accessibilityHidden(true)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(colorScheme == .dark ? Color(red: 1.0, green: 0.82, blue: 0.42) : Color(red: 0.43, green: 0.25, blue: 0.03))
                            .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.14), in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityHint(app.tr("Cheques"))
                            .accessibilityIdentifier("shortfallDetails")
                        } else if let ending = outlook.points.last(where: { !$0.contributors.isEmpty }) ?? outlook.points.last {
                            let value = hidesAmounts || ending.balance <= 0 ? money(ending.balance) : "+" + money(ending.balance)
                            Label(app.tr("Cash forecast") + " · " + app.formatDay(ending.day) + " · " + value,
                                  systemImage: "chart.xyaxis.line")
                        }
                    }
                } else {
                    Button { showingPlus = true } label: { Label(app.tr("Cash forecast") + " · " + app.tr("Shekati Plus"), systemImage: "chart.xyaxis.line") }
                }
            } else {
                Label(app.tr("Review the conflicting entries before continuing."), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $showingPlus) { ShekatiPlusView() }
    }
}

@MainActor
private struct LiquidityForecast: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    let account: BankAccountRecord
    let focusDay: LocalDay?
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var horizon: Int

    init(account: BankAccountRecord, focusDay: LocalDay?, today: LocalDay) {
        self.account = account
        self.focusDay = focusDay
        _horizon = State(initialValue: focusDay.map { $0 > today.adding(days: 30) } == true ? 60 : 30)
    }
    @State private var report = ChequeTransferDocument(data: Data())
    @State private var exportingReport = false

    var body: some View {
        List {
            Picker(app.tr("Forecast duration"), selection: $horizon) {
                Text(app.tr("30 days")).tag(30)
                Text(app.tr("60 days")).tag(60)
            }.pickerStyle(.segmented)
            if let outlook = try? BankingLedger.outlook(account: account, records: records, events: events, today: app.today, horizon: horizon) {
                if let focusDay, let point = outlook.points.first(where: { $0.day == focusDay && $0.balance < 0 }) {
                    Section {
                        let value = hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: point.balance, currencyCode: account.currencyCode, locale: app.preferences.language.locale)
                        LabeledContent(app.formatDay(point.day), value: value)
                        contributors(for: point)
                    } header: { Label(app.tr("Expected shortfall"), systemImage: "exclamationmark.triangle") }
                }
                if !hidesAmounts {
                    let digits = CurrencyMath.fractionDigits(for: account.currencyCode)
                    let divisor = pow(10.0, Double(digits))
                    Chart(outlook.points) { point in
                        LineMark(x: .value(app.tr("Date"), point.day.date()), y: .value(account.currencyCode, Double(point.balance) / divisor))
                            .interpolationMethod(.stepEnd)
                        RuleMark(y: .value(account.currencyCode, 0)).foregroundStyle(.secondary)
                    }.chartYAxisLabel(account.currencyCode).frame(height: 175)
                }
                Text(app.tr("Assumes incoming cheques are collected on their due dates.")).font(.footnote)
                if !hidesAmounts {
                    Button(app.tr("Export forecast PDF")) {
                        report = ChequeTransferDocument(data: CashFlowReport.generate(outlook, account: account, language: app.preferences.language))
                        exportingReport = true
                    }
                }
                ForEach(outlook.points) { point in
                    Section {
                        contributors(for: point)
                    } header: {
                        let amount = hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: point.balance, currencyCode: account.currencyCode, locale: app.preferences.language.locale)
                        Text(app.formatDay(point.day) + " · " + amount)
                    }
                }
            } else { Text(app.tr("Review the conflicting entries before continuing.")) }
        }.navigationTitle(app.tr("Cash forecast"))
            .fileExporter(isPresented: $exportingReport, document: report, contentType: .pdf, defaultFilename: "Shekati-\(app.today.iso).pdf") { result in
                if case .failure = result { app.persistenceMessage = app.tr("The file could not be saved. Please try again.") }
            }
    }

    @ViewBuilder private func contributors(for point: CashPoint) -> some View {
        ForEach(point.contributors, id: \.self) { id in
            if let record = records.first(where: { $0.id == id }) {
                NavigationLink {
                    ChequeDetailView(record: record)
                } label: {
                    ChequeRowView(record: record, position: BankingLedger.position(for: record, events: events))
                }
            }
        }
    }
}
