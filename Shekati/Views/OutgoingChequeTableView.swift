import SwiftUI
import SwiftData
import ShekatiCore

/// The Cheques tab: every outgoing cheque laid out like the owner's "postdated cheques" sheet.
/// Columns, from the leading edge (the right in Arabic): value with a data bar, payee, cheque
/// number, cheque date and the balance still owed from that row onward. Display only; a row
/// opens its cheque. Paid rows are green, a returned or missing number is red, the balance is yellow.
@MainActor
struct OutgoingChequeTableView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<ChequeRecord> { $0.deletedAt == nil && $0.directionRaw == "outgoing" })
    private var records: [ChequeRecord]

    var body: some View {
        let ledger = OutgoingChequeLedger(cheques: records.map(\.snapshot))
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(ledger.rows) { row in
                        if let record = byID[row.id] {
                            NavigationLink { ChequeDetailView(record: record) } label: {
                                OutgoingChequeRow(row: row, showsBalance: !ledger.hasCurrencyConflict)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if ledger.rows.isEmpty {
                        ContentUnavailableView(app.tr("No outgoing cheques"), systemImage: "doc.text",
                                               description: Text(app.tr("Outgoing cheques you add appear here in date order.")))
                            .padding(.top, 32)
                    }
                } header: {
                    OutgoingChequeTableHeader()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(app.tr("Cheques"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Column widths as percentages of the screen width, in leading-to-trailing order.
enum OutgoingChequeColumn {
    static let amount = 22
    static let payee = 30
    static let number = 14
    static let date = 19
    static let balance = 15
}

/// Sheet colours. Filled cells always use black text so they stay readable in dark mode.
@MainActor
enum OutgoingChequeStyle {
    static let title = Color(red: 1, green: 1, blue: 0)
    static let balance = Color(red: 1, green: 1, blue: 0)
    static let paid = Color(red: 0.573, green: 0.816, blue: 0.314)
    static let flagged = Color(red: 1, green: 0, blue: 0)
    static let bar = Color(red: 0.97, green: 0.35, blue: 0.38)
    static let grid = Color.primary.opacity(0.55)
    static let cell = Color(uiColor: .systemBackground)
}

/// One bordered sheet cell spanning a percentage of the screen width. Cells in a row share its height.
@MainActor
private struct SheetCell<Content: View>: View {
    let span: Int
    var fill: Color? = nil
    var alignment: Alignment = .center
    /// An Excel-style data bar from the leading edge, as a fraction of the cell width.
    var bar: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(fill == nil ? Color.primary : Color.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: .infinity, alignment: alignment)
            .containerRelativeFrame(.horizontal, count: 100, span: span, spacing: 0)
            .background(alignment: .leading) {
                if bar > 0 {
                    Rectangle()
                        .fill(LinearGradient(colors: [OutgoingChequeStyle.bar.opacity(0.9), OutgoingChequeStyle.bar.opacity(0.2)],
                                             startPoint: .leading, endPoint: .trailing))
                        // Gradients are drawn left to right; mirror so the solid end sits on the leading edge.
                        .flipsForRightToLeftLayoutDirection(true)
                        .containerRelativeFrame(.horizontal) { [span, bar] length, _ in
                            length * CGFloat(span) / 100 * CGFloat(min(1, bar))
                        }
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                }
            }
            .background(fill ?? OutgoingChequeStyle.cell, ignoresSafeAreaEdges: [])
            .border(OutgoingChequeStyle.grid, width: 0.5)
    }
}

@MainActor
private struct OutgoingChequeTableHeader: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Text(app.tr("Postdated cheques"))
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(OutgoingChequeStyle.title, ignoresSafeAreaEdges: [])
                .border(OutgoingChequeStyle.grid, width: 0.5)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("outgoingTableTitle")
            HStack(spacing: 0) {
                heading("Value", span: OutgoingChequeColumn.amount)
                heading("Pay to", span: OutgoingChequeColumn.payee)
                heading("Cheque no.", span: OutgoingChequeColumn.number)
                heading("Cheque date", span: OutgoingChequeColumn.date)
                heading("Balance", span: OutgoingChequeColumn.balance)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(OutgoingChequeStyle.cell, ignoresSafeAreaEdges: [])
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func heading(_ key: String, span: Int) -> some View {
        SheetCell(span: span) {
            Text(app.tr(key))
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct OutgoingChequeRow: View {
    @Environment(AppState.self) private var app
    let row: OutgoingChequeLedger.Row
    let showsBalance: Bool

    private var cheque: ChequeSnapshot { row.cheque }
    private var number: String { cheque.number.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var amount: String { CurrencyMath.plain(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode) }
    private var date: String { OutgoingChequeLedger.dateText(cheque.dueDate) }
    private var balance: String {
        guard showsBalance, let remaining = row.remainingMinorUnits else { return "—" }
        return CurrencyMath.plain(minorUnits: remaining, currencyCode: cheque.currencyCode)
    }
    private var rowFill: Color? { cheque.status == .settled ? OutgoingChequeStyle.paid : nil }
    private var numberFill: Color? {
        cheque.status == .returned || number.isEmpty ? OutgoingChequeStyle.flagged : rowFill
    }
    private var cancelled: Bool { cheque.status == .cancelled }

    var body: some View {
        HStack(spacing: 0) {
            amountCell
            SheetCell(span: OutgoingChequeColumn.payee, fill: rowFill) {
                Text(cheque.party.isEmpty ? "—" : cheque.party)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            SheetCell(span: OutgoingChequeColumn.number, fill: numberFill) {
                numeric(number)
            }
            SheetCell(span: OutgoingChequeColumn.date, fill: rowFill) {
                numeric(date)
            }
            SheetCell(span: OutgoingChequeColumn.balance, fill: OutgoingChequeStyle.balance) {
                numeric(balance)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // A five-column sheet cannot grow without limit on an iPhone; numbers also shrink to fit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .opacity(cancelled ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibleDescription))
        .accessibilityIdentifier("cheque-row-\(cheque.id.uuidString)")
    }

    private var amountCell: some View {
        // The bar is scaled to the largest listed amount, like the sheet's data bars.
        SheetCell(span: OutgoingChequeColumn.amount, fill: rowFill, alignment: .trailing, bar: row.barFraction) {
            numeric(amount).strikethrough(cancelled)
        }
    }

    /// Numbers keep their left-to-right order and shrink rather than truncate in a narrow column.
    private func numeric(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .environment(\.layoutDirection, .leftToRight)
    }

    private var statusLabel: String {
        switch cheque.status {
        case .pending: return app.tr(cheque.isOverdue(on: app.today) ? "Overdue" : "Pending")
        case .settled: return app.tr("Paid")
        case .returned: return app.tr("Returned")
        case .cancelled: return app.tr("Cancelled")
        }
    }

    private var accessibleDescription: String {
        let title = cheque.party.isEmpty ? app.tr("Cheque") : cheque.party
        return [title,
                "\(app.tr("No.")) \(number.isEmpty ? app.tr("Not provided") : number)",
                "\(amount) \(cheque.currencyCode)",
                "\(app.tr("Due date")) \(date)",
                statusLabel,
                "\(app.tr("Balance")) \(balance)"].joined(separator: ", ")
    }
}
