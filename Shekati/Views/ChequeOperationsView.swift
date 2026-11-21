import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct ChequeOperationsView: View {
    let record: ChequeRecord
    let isPlus: Bool
    var hidesAmounts = false
    var showsFinancialSummary = true
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var events: [LedgerEventRecord]
    @Query(sort: \BankAccountRecord.createdAt) private var accounts: [BankAccountRecord]
    @Query private var books: [ChequeBookRecord]
    @State private var selectedAccount: UUID?
    @State private var selectedBook: UUID?
    @State private var sheet: OperationIntent?
    @State private var plus = false
    @State private var error: String?

    private var position: ChequePosition { BankingLedger.position(for: record, events: events) }
    private var matchingAccounts: [BankAccountRecord] { accounts.filter { $0.currencyCode == record.currencyCode } }
    private var history: [LedgerOperation] {
        let operations = events.filter { $0.chequeID == record.id }.compactMap(\.operation)
        let index = Dictionary(operations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ranks: [UUID: Int] = [:]
        for event in index.values {
            var cursor: LedgerOperation? = event
            var path: [UUID] = []
            var seen = Set<UUID>()
            while let item = cursor, ranks[item.id] == nil, seen.insert(item.id).inserted {
                path.append(item.id)
                let previous = item.kind == .discardConflict ? item.relatedID : item.parentID
                cursor = previous.flatMap { index[$0] }
            }
            var depth = cursor.flatMap { ranks[$0.id] } ?? 0
            for id in path.reversed() {
                depth += 1
                ranks[id] = depth
            }
        }
        return index.values.sorted {
            if $0.day != $1.day { return $0.day > $1.day }
            if ranks[$0.id] != ranks[$1.id] { return ranks[$0.id, default: 0] > ranks[$1.id, default: 0] }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private func begin(_ action: LedgerAction) {
        if action.isPremium && !isPlus { plus = true }
        else { sheet = OperationIntent(action: action, parent: position.accepted.last?.id, related: nil) }
    }
    private func money(_ minor: Int64) -> String {
        hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: minor, currencyCode: record.currencyCode, locale: app.preferences.language.locale)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsFinancialSummary {
                Text(app.tr(position.state.title)).font(.headline)
                if position.conflicts.isEmpty {
                    ResponsiveValueRow(title: app.tr("Amount paid"), value: money(position.paid))
                    ResponsiveValueRow(title: app.tr("Remaining amount"), value: money(position.remaining))
                }
            }
            if !position.holder.isEmpty { ResponsiveValueRow(title: app.tr("Current holder"), value: position.holder) }
            if !position.conflicts.isEmpty {
                Label(app.tr("Review conflicting entries"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                ForEach(position.conflicts) { op in
                    Button {
                        sheet = OperationIntent(action: .discardConflict, parent: nil, related: op)
                    } label: {
                        Text(app.tr(op.kind.title) + " · " + money(op.amount) + " · " + app.formatDay(op.day))
                    }
                }
            } else if BankingLedger.canSettleHistorically(record, accounts: accounts, events: events, isPlus: isPlus) {
                Button {
                    sheet = OperationIntent(action: .historicalSettlement, parent: nil, related: nil,
                                            historicalAmount: position.remaining, historicalCurrency: record.currencyCode)
                } label: {
                    Label(app.tr(LedgerAction.historicalSettlement.title), systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.onAccent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("operation-historicalSettlement")
                NavigationLink(app.tr("Bank accounts")) { BankingAccountsView(isPlus: isPlus) }
            } else if record.bankAccountID == nil && position.isOpen {
                Text(app.tr("Select a bank account in the cheque currency.")).font(.subheadline)
                Picker(app.tr("Bank account"), selection: $selectedAccount) {
                    Text(app.tr("Choose")).tag(UUID?.none)
                    ForEach(matchingAccounts) { Text($0.name).tag(Optional($0.id)) }
                }
                if record.direction == .outgoing {
                    Picker(app.tr("Cheque book"), selection: $selectedBook) {
                        Text(app.tr("Choose")).tag(UUID?.none)
                        ForEach(books.filter { $0.accountID == selectedAccount }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Button(app.tr("Link account")) {
                    do {
                        guard let account = matchingAccounts.first(where: { $0.id == selectedAccount }) else { throw BankingError.accountRequired }
                        try BankingLedger.link(record: record, account: account, book: books.first(where: { $0.id == selectedBook }), context: context)
                        app.didMutate()
                    } catch { self.error = error.localizedDescription }
                }.disabled(selectedAccount == nil || (record.direction == .outgoing && selectedBook == nil))
                NavigationLink(app.tr("Bank accounts")) { BankingAccountsView(isPlus: isPlus) }
            } else {
                let main = position.allowed.first(where: { !$0.isPremium }) ?? position.allowed.first
                if let main {
                    Button { begin(main) } label: {
                        Label(app.tr(main.title), systemImage: main == .deposit ? "tray.and.arrow.down" : "checkmark.circle")
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("operation-" + main.rawValue)
                }
                let others = position.allowed.filter { $0 != main }
                if !others.isEmpty || position.accepted.last != nil {
                    Menu {
                        ForEach(others, id: \.self) { action in
                            Button { begin(action) } label: {
                                Label(app.tr(action.title), systemImage: action.isPremium && !isPlus ? "lock" : "arrow.forward.circle")
                            }.accessibilityIdentifier("operation-" + action.rawValue)
                        }
                        if let last = position.accepted.last {
                            Button(app.tr("Correct last action"), role: .destructive) {
                                sheet = OperationIntent(action: .discardConflict, parent: nil, related: last, correctsLastAction: true)
                            }
                        }
                    } label: {
                        Label(app.tr("Cheque actions"), systemImage: "ellipsis.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("moreChequeActions")
                }
            }
            if let error { Text(app.tr(error)).foregroundStyle(.red) }
            if !history.isEmpty {
                Divider()
                Text(app.tr("Activity history")).font(.headline)
                ForEach(history) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.tr(event.kind == .discardConflict ? "Previous entry excluded" : event.kind.title))
                        Text([app.formatDay(event.day), event.amount == 0 ? "" : money(event.amount), event.party]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Divider()
                Label(app.tr("Date added") + " · " + app.formatDay(LocalDay(date: record.createdAt)), systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $sheet) { intent in
            OperationForm(record: record, intent: intent, remaining: position.remaining, isPlus: isPlus, hidesAmounts: hidesAmounts)
        }
        .sheet(isPresented: $plus) { NavigationStack { ShekatiPlusView() } }
    }
}

private struct OperationIntent: Identifiable {
    let id = UUID()
    let action: LedgerAction
    let parent: UUID?
    let related: LedgerOperation?
    var correctsLastAction = false
    var historicalAmount: Int64?
    var historicalCurrency: String?

    var title: String { correctsLastAction ? "Correct last action" : action.title }
}

@MainActor
private struct OperationForm: View {
    let record: ChequeRecord
    let intent: OperationIntent
    let remaining: Int64
    let isPlus: Bool
    let hidesAmounts: Bool
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [BankAccountRecord]
    @State private var amount = ""
    @State private var party = ""
    @State private var number = ""
    @State private var date = Date()
    @State private var due = Date()
    @State private var confirmation = false
    @State private var error: String?
    private var partial: Bool { [.partialBank, .partialCash].contains(intent.action) }
    private var effectiveAmount: Int64? {
        if intent.action == .historicalSettlement { return intent.historicalAmount }
        return partial ? CurrencyMath.parseMinorUnits(amount, currencyCode: record.currencyCode) :
            ([.settle, .acknowledgeEndorsement, .replace].contains(intent.action) ? remaining : 0)
    }
    private func display(_ value: Int64) -> String {
        hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: value, currencyCode: intent.historicalCurrency ?? record.currencyCode, locale: app.preferences.language.locale)
    }
    private var remainderAfterPayment: Int64? {
        guard partial, let value = effectiveAmount, value > 0, value <= remaining else { return nil }
        return remaining - value
    }
    private var summary: String {
        let amountText = display(effectiveAmount ?? 0)
        let accountName = intent.action == .historicalSettlement ? "" : accounts.first(where: { $0.id == record.bankAccountID })?.name ?? ""
        let parts = [app.tr(intent.title), record.number, app.formatDay(LocalDay(date: date)), (effectiveAmount ?? 0) == 0 ? "" : amountText,
                     accountName, party, number,
                     intent.action == .replace ? app.formatDay(LocalDay(date: due)) : "",
                     remainderAfterPayment.map { app.tr("Remaining after payment") + " · " + display($0) } ?? ""]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(app.tr("Cheque number"), value: record.number)
                if let related = intent.related {
                    LabeledContent(app.tr("Action to reverse"), value: app.tr(related.kind.title) + " · " + app.formatDay(related.day))
                    Text(app.tr("The reversal is recorded in the activity history.")).font(.footnote)
                } else if intent.action == .historicalSettlement, let issued = record.issueDate, issued <= .today {
                    DatePicker(app.tr("Date"), selection: $date, in: Calendar.current.startOfDay(for: issued.date())...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("operationDate")
                } else {
                    DatePicker(app.tr("Date"), selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("operationDate")
                }
                if partial {
                    LabeledContent(app.tr("Original amount"), value: display(record.amountMinorUnits))
                    LabeledContent(app.tr("Remaining"), value: display(remaining))
                    if hidesAmounts {
                        SecureField(app.tr("Amount"), text: $amount).keyboardType(.decimalPad)
                    } else {
                        TextField(app.tr("Amount"), text: $amount).keyboardType(.decimalPad)
                    }
                    if let after = remainderAfterPayment {
                        LabeledContent(app.tr("Remaining after payment"), value: display(after))
                    }
                }
                if intent.action == .historicalSettlement, let historicalAmount = intent.historicalAmount {
                    LabeledContent(app.tr("Amount"), value: display(historicalAmount))
                    Text(app.tr(LedgerAction.historicalSettlement.title)).font(.footnote)
                } else if let account = accounts.first(where: { $0.id == record.bankAccountID }) {
                    LabeledContent(app.tr("Bank account"), value: account.name)
                }
                if intent.action == .endorse {
                    TextField(app.tr("New holder"), text: $party)
                    Text(app.tr("The cheque stays in follow-up until the new holder confirms collection.")).font(.footnote)
                } else if [.discardConflict, .markReturned, .cancel, .historicalSettlement].contains(intent.action) {
                    TextField(app.tr("Reason"), text: $party)
                }
                if intent.action == .replace {
                    TextField(app.tr("Replacement cheque number"), text: $number)
                    TextField(app.tr("Reason"), text: $party)
                    DatePicker(app.tr("Replacement due date"), selection: $due, in: Calendar.current.startOfDay(for: date)..., displayedComponents: .date)
                }
                if intent.action == .deposit {
                    Text(app.tr("The bank balance changes when collection is confirmed.")).font(.footnote)
                }
                if let error { Text(app.tr(error)).foregroundStyle(.red) }
                Button(app.tr("Review action")) { confirmation = true }
                    .accessibilityIdentifier("reviewOperation")
                    .disabled(effectiveAmount == nil || (partial && remainderAfterPayment == nil) ||
                              ([.endorse, .discardConflict, .markReturned, .cancel, .historicalSettlement].contains(intent.action) && party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                              (intent.action == .replace && number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .navigationTitle(app.tr(intent.title)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { dismiss() } } }
            .confirmationDialog(app.tr("Confirm action"), isPresented: $confirmation, titleVisibility: .visible) {
                Button(app.tr("Confirm")) { commit() }.accessibilityIdentifier("commitOperation")
                Button(app.tr("Cancel"), role: .cancel) {}
            } message: { Text(summary) }
        }
    }
    private func commit() {
        do {
            if let rejected = intent.related {
                try BankingLedger.dismissConflict(rejected, reason: party, record: record, context: context)
            } else if intent.action == .historicalSettlement {
                guard let amount = intent.historicalAmount, let currency = intent.historicalCurrency else { throw BankingError.invalid }
                try BankingLedger.settleHistorically(record, operationID: intent.id, amount: amount, currency: currency,
                                                     day: LocalDay(date: date), reason: party, isPlus: isPlus, context: context)
            } else {
                try BankingLedger.perform(intent.action, for: record, amount: effectiveAmount ?? 0, day: LocalDay(date: date),
                                          party: party, replacementNumber: number, replacementDue: LocalDay(date: due),
                                          expectedParent: intent.parent, isPlus: isPlus, context: context)
            }
            app.didMutate(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
