import SwiftUI
import SwiftData
import ShekatiCore

/// The outgoing ledger keeps paid records in their own tab without deleting their history.
@MainActor
struct OutgoingChequeTableView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<ChequeRecord> { $0.deletedAt == nil && $0.directionRaw == "outgoing" })
    private var records: [ChequeRecord]
    @State private var showsPaid = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingFreeDays = false
    @State private var showingEditor = false

    var body: some View {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshots = byID.values.filter { showsPaid ? $0.status == .settled : $0.status != .settled }.map(\.snapshot)
        let ledger = OutgoingChequeLedger(cheques: snapshots)
        let visibleIDs = Set(ledger.rows.map(\.id))
        let selected = ChequeSelectionSummary(cheques: snapshots, selectedIDs: selectedIDs)
        VStack(spacing: 0) {
            scopePicker.padding(.horizontal, 16).padding(.top, 8)
            listActions(visibleIDs: visibleIDs).padding(.horizontal, 16).padding(.vertical, 8)
            if isSelecting {
                selectionActions(visibleIDs: visibleIDs).padding(.horizontal, 16).padding(.bottom, 8)
            }
            tableContent(ledger, byID: byID)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(app.tr("Cheques"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    endSelection()
                    showingEditor = true
                } label: { Image(systemName: "plus") }
                .accessibilityLabel(app.tr("Add cheque"))
                .accessibilityIdentifier("addOutgoingCheque")
                .disabled(app.currencyConflict || app.currencyCode.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { ChequeSelectionSummaryView(summary: selected) }
        }
        .onChange(of: showsPaid) { _, _ in endSelection() }
        .onChange(of: visibleIDs) { _, ids in selectedIDs.formIntersection(ids) }
        .sheet(isPresented: $showingFreeDays) { ChequeFreeDaysView() }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { ChequeEditorView(initialDirection: .outgoing) }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, app.preferences.language == .arabic ? .rightToLeft : .leftToRight)
        }
    }

    @ViewBuilder private var scopePicker: some View {
        if dynamicTypeSize.isAccessibilitySize { scopeSelection.pickerStyle(.menu) }
        else { scopeSelection.pickerStyle(.segmented) }
    }

    private var scopeSelection: some View {
        Picker(app.tr("Show cheques"), selection: $showsPaid) {
            Text(app.tr("Cheques")).tag(false)
            Text(app.tr("Paid cheques")).tag(true)
        }
        .accessibilityIdentifier("outgoingPaymentScopePicker")
    }

    private func listActions(visibleIDs: Set<UUID>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                freeDaysButton.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                selectionButton(visibleIDs: visibleIDs).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                freeDaysButton
                selectionButton(visibleIDs: visibleIDs)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
    }

    private var freeDaysButton: some View {
        Button {
            endSelection()
            showingFreeDays = true
        } label: { Label(app.tr("Free due dates"), systemImage: "calendar.badge.plus").frame(minHeight: 44) }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("freeChequeDaysButton")
    }

    private func selectionButton(visibleIDs: Set<UUID>) -> some View {
        Button(app.tr(isSelecting ? "Done" : "Select")) {
            if isSelecting { endSelection() }
            else { selectedIDs.removeAll(); isSelecting = true }
        }
        .fontWeight(.semibold)
        .frame(minHeight: 44)
        .buttonStyle(.borderless)
        .disabled(visibleIDs.isEmpty && !isSelecting)
        .accessibilityIdentifier("selectChequesButton")
    }

    private func selectionActions(visibleIDs: Set<UUID>) -> some View {
        HStack {
            Button(app.tr("Select all")) { selectedIDs = visibleIDs }
                .accessibilityIdentifier("selectAllChequesButton")
                .disabled(visibleIDs.isEmpty || selectedIDs == visibleIDs)
            Spacer(minLength: 12)
            Button(app.tr("Clear selection")) { selectedIDs.removeAll() }
                .accessibilityIdentifier("clearSelectedChequesButton")
                .disabled(selectedIDs.isEmpty)
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
    }

    private func endSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func tableContent(_ ledger: OutgoingChequeLedger, byID: [UUID: ChequeRecord]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(ledger.rows) { row in
                        if let record = byID[row.id] {
                            if isSelecting {
                                Button {
                                    if selectedIDs.contains(row.id) { selectedIDs.remove(row.id) }
                                    else { selectedIDs.insert(row.id) }
                                } label: {
                                    OutgoingChequeRow(row: row, showsBalance: !ledger.hasCurrencyConflict,
                                        showsPaidDates: showsPaid, isSelecting: true, isSelected: selectedIDs.contains(row.id))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selectedIDs.contains(row.id) ? .isSelected : [])
                                .accessibilityValue(app.tr(selectedIDs.contains(row.id) ? "Selected" : "Not selected"))
                            } else {
                                NavigationLink { ChequeDetailView(record: record) } label: {
                                    OutgoingChequeRow(row: row, showsBalance: !ledger.hasCurrencyConflict, showsPaidDates: showsPaid)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if ledger.rows.isEmpty {
                        ContentUnavailableView(app.tr(showsPaid ? "No paid cheques" : "No outgoing cheques"),
                                               systemImage: showsPaid ? "checkmark.circle" : "doc.text",
                                               description: Text(app.tr(showsPaid
                                                ? "Paid cheques appear here with their details and payment dates."
                                                : "Outgoing cheques you add appear here in date order.")))
                            .padding(.top, 32)
                    }
                } header: {
                    OutgoingChequeTableHeader(showsPaidDates: showsPaid, isSelecting: isSelecting)
                }
            }
        }
        .accessibilityIdentifier("outgoingChequeTable")
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
    var showsPaidDates = false
    var isSelecting = false

    var body: some View {
        VStack(spacing: 0) {
            Text(app.tr(showsPaidDates ? "Paid cheques" : "Postdated cheques"))
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
                heading(isSelecting ? "Select" : (showsPaidDates ? "Payment date" : "Balance"), span: OutgoingChequeColumn.balance)
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
    var showsPaidDates = false
    var isSelecting = false
    var isSelected = false

    private var cheque: ChequeSnapshot { row.cheque }
    private var number: String { NumericInput.latinDigits(cheque.number.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var amount: String { CurrencyMath.plain(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode) }
    private var date: String { OutgoingChequeLedger.dateText(cheque.dueDate) }
    private var paymentDate: String { cheque.actualDate.map(OutgoingChequeLedger.dateText) ?? "—" }
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
                Text(cheque.party.isEmpty ? "—" : NumericInput.latinDigits(cheque.party))
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
            if isSelecting {
                SheetCell(span: OutgoingChequeColumn.balance) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            } else {
                SheetCell(span: OutgoingChequeColumn.balance, fill: showsPaidDates ? rowFill : OutgoingChequeStyle.balance) {
                    numeric(showsPaidDates ? paymentDate : balance)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // A five-column sheet cannot grow without limit on an iPhone; numbers also shrink to fit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .opacity(cancelled ? 0.55 : 1)
        .contentShape(Rectangle())
        .overlay { if isSelecting && isSelected { Rectangle().strokeBorder(Theme.accent, lineWidth: 2).allowsHitTesting(false) } }
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
        let title = cheque.party.isEmpty ? app.tr("Cheque") : NumericInput.latinDigits(cheque.party)
        return [title,
                "\(app.tr("No.")) \(number.isEmpty ? app.tr("Not provided") : number)",
                "\(amount) \(cheque.currencyCode)",
                "\(app.tr("Due date")) \(date)",
                statusLabel,
                showsPaidDates ? "\(app.tr("Payment date")) \(paymentDate)" : "\(app.tr("Balance")) \(balance)"].joined(separator: ", ")
    }
}
