import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct ChequeOperationsView: View {
    let record: ChequeRecord
    let isPlus: Bool
    var hidesAmounts = false
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
        events.filter { $0.chequeID == record.id }.compactMap(\.operation).sorted {
            if $0.day != $1.day { return $0.day > $1.day }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private func money(_ minor: Int64) -> String {
        hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: minor, currencyCode: record.currencyCode, locale: app.preferences.language.locale)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.tr(position.state.title)).font(.headline)
            ResponsiveValueRow(title: app.tr("Amount paid"), value: money(position.paid))
            ResponsiveValueRow(title: app.tr("Remaining amount"), value: money(position.remaining))
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
                ForEach(position.allowed, id: \.self) { action in
                    Button {
                        if action.isPremium && !isPlus { plus = true }
                        else { sheet = OperationIntent(action: action, parent: position.accepted.last?.id, related: nil) }
                    } label: {
                        Label(app.tr(action.title), systemImage: action.isPremium && !isPlus ? "lock" : "arrow.forward.circle")
                    }.buttonStyle(.bordered)
                }
            }
            if let error { Text(app.tr(error)).foregroundStyle(.red) }
            if !history.isEmpty {
                Divider()
                Text(app.tr("Activity history")).font(.headline)
                ForEach(history) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.tr(event.kind.title))
                        Text([app.formatDay(event.day), event.amount == 0 ? "" : money(event.amount), event.party]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
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
        partial ? CurrencyMath.parseMinorUnits(amount, currencyCode: record.currencyCode) :
            ([.settle, .acknowledgeEndorsement, .replace].contains(intent.action) ? remaining : 0)
    }
    private var summary: String {
        let amountText = hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: effectiveAmount ?? 0, currencyCode: record.currencyCode, locale: app.preferences.language.locale)
        let parts = [app.tr(intent.action.title), record.number, app.formatDay(LocalDay(date: date)), (effectiveAmount ?? 0) == 0 ? "" : amountText,
                     accounts.first(where: { $0.id == record.bankAccountID })?.name ?? "", party, number,
                     intent.action == .replace ? app.formatDay(LocalDay(date: due)) : ""]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(app.tr("Cheque number"), value: record.number)
                DatePicker(app.tr("Date"), selection: $date, in: ...Date(), displayedComponents: .date)
                if partial {
                    TextField(app.tr("Amount"), text: $amount).keyboardType(.decimalPad)
                }
                if let account = accounts.first(where: { $0.id == record.bankAccountID }) {
                    LabeledContent(app.tr("Bank account"), value: account.name)
                }
                if intent.action == .endorse {
                    TextField(app.tr("New holder"), text: $party)
                } else if intent.action == .discardConflict || intent.action == .markReturned || intent.action == .cancel {
                    TextField(app.tr("Reason"), text: $party)
                }
                if intent.action == .replace {
                    TextField(app.tr("Replacement cheque number"), text: $number)
                    DatePicker(app.tr("Replacement due date"), selection: $due, in: Calendar.current.startOfDay(for: date)..., displayedComponents: .date)
                }
                if intent.action == .deposit {
                    Text(app.tr("The bank balance changes when collection is confirmed.")).font(.footnote)
                }
                if let error { Text(app.tr(error)).foregroundStyle(.red) }
                Button(app.tr("Review action")) { confirmation = true }
                    .disabled(effectiveAmount == nil || (partial && (effectiveAmount ?? 0) > remaining) ||
                              ([.endorse, .discardConflict, .markReturned, .cancel].contains(intent.action) && party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                              (intent.action == .replace && number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .navigationTitle(app.tr(intent.action.title)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Cancel")) { dismiss() } } }
            .confirmationDialog(app.tr("Confirm action"), isPresented: $confirmation, titleVisibility: .visible) {
                Button(app.tr("Confirm")) { commit() }
                Button(app.tr("Cancel"), role: .cancel) {}
            } message: { Text(summary) }
        }
    }
    private func commit() {
        do {
            if let rejected = intent.related {
                try BankingLedger.dismissConflict(rejected, reason: party, record: record, context: context)
            } else {
                try BankingLedger.perform(intent.action, for: record, amount: effectiveAmount ?? 0, day: LocalDay(date: date),
                                          party: party, replacementNumber: number, replacementDue: LocalDay(date: due),
                                          expectedParent: intent.parent, isPlus: isPlus, context: context)
            }
            app.didMutate(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
