import SwiftUI
import SwiftData
import ShekatiCore

/// The outgoing ledger keeps paid records in their own tab without deleting their history.
@MainActor
struct OutgoingChequeTableView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .footnote) private var minimumTableWidth: CGFloat = 620
    @ScaledMetric(relativeTo: .footnote) private var digitWidth: CGFloat = 8
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleContent(ledger, byID: byID, visibleIDs: visibleIDs, selected: selected)
            } else {
                VStack(spacing: 0) {
                    if verticalSizeClass == .compact {
                        compactControls(visibleIDs: visibleIDs)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                    } else {
                        scopePicker.padding(.horizontal, 16).padding(.top, 8)
                        listActions(visibleIDs: visibleIDs).padding(.horizontal, 16).padding(.vertical, 8)
                        if isSelecting {
                            selectionActions(visibleIDs: visibleIDs).padding(.horizontal, 16).padding(.bottom, 8)
                        }
                    }
                    tableContent(ledger, byID: byID)
                }
            }
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
            if isSelecting && !dynamicTypeSize.isAccessibilitySize {
                ChequeSelectionSummaryView(summary: selected, compact: verticalSizeClass == .compact)
            }
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

    private func compactControls(visibleIDs: Set<UUID>) -> some View {
        HStack(spacing: 16) {
            scopeSelection.pickerStyle(.menu).labelsHidden()
            Spacer(minLength: 0)
            freeDaysButton
            selectionButton(visibleIDs: visibleIDs)
            if isSelecting {
                Menu {
                    Button(app.tr("Select all")) { selectedIDs = visibleIDs }
                        .disabled(visibleIDs.isEmpty || selectedIDs == visibleIDs)
                        .accessibilityIdentifier("selectAllChequesButton")
                    Button(app.tr("Clear selection")) { selectedIDs.removeAll() }
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityIdentifier("clearSelectedChequesButton")
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel(app.tr("Selected cheques"))
                .accessibilityIdentifier("chequeSelectionActions")
            }
        }
        .font(.subheadline)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(app.tr("Select all")) { selectedIDs = visibleIDs }
                .frame(minHeight: 44)
                .accessibilityIdentifier("selectAllChequesButton")
                .disabled(visibleIDs.isEmpty || selectedIDs == visibleIDs)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Button(app.tr("Clear selection")) { selectedIDs.removeAll() }
                .frame(minHeight: 44)
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
        GeometryReader { geometry in
            let width = ledger.rows.isEmpty ? geometry.size.width : max(geometry.size.width, readableWidth(for: ledger))
            // Keep the sheet's text readable. Narrow displays pan horizontally instead
            // of reducing dates and amounts to tiny fractions of the preferred font.
            VStack(spacing: 0) {
                if width > geometry.size.width + 1 {
                    Label(app.tr("Swipe to see all columns"), systemImage: "arrow.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .accessibilityIdentifier("ledgerHorizontalScrollHint")
                }
                OutgoingChequeTableTitle(showsPaidDates: showsPaid)
                GeometryReader { tableGeometry in
                    ScrollView(.horizontal) {
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                Section {
                                    ledgerRows(ledger, byID: byID)
                                    if ledger.rows.isEmpty { emptyLedger }
                                } header: {
                                    OutgoingChequeTableHeader(showsPaidDates: showsPaid, isSelecting: isSelecting)
                                }
                            }
                        }
                        .frame(width: width, height: tableGeometry.size.height)
                        .environment(\.layoutDirection, app.preferences.language == .arabic ? .rightToLeft : .leftToRight)
                    }
                    // Use a physical scroll axis with an explicit starting edge. The
                    // sheet itself retains the selected language's column direction.
                    .defaultScrollAnchor(app.preferences.language == .arabic ? .topTrailing : .topLeading)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("outgoingChequeTable")
                }
            }
        }
    }

    private func readableWidth(for ledger: OutgoingChequeLedger) -> CGFloat {
        var width = minimumTableWidth
        for row in ledger.rows {
            let fields: [(String, Int)] = [
                (NumericInput.latinDigits(row.cheque.number), OutgoingChequeColumn.number),
                (CurrencyMath.plain(minorUnits: row.cheque.amountMinorUnits, currencyCode: row.cheque.currencyCode), OutgoingChequeColumn.amount),
                (showsPaid ? "00/00/0000" : row.remainingMinorUnits.map {
                    CurrencyMath.plain(minorUnits: $0, currencyCode: row.cheque.currencyCode)
                } ?? "—", OutgoingChequeColumn.balance)
            ]
            for (text, span) in fields {
                // Unusually long references can wrap; never allocate an unbounded sheet.
                width = max(width, (CGFloat(min(text.count, 28)) * digitWidth + 12) * 100 / CGFloat(span))
            }
        }
        return width
    }

    private func accessibleContent(_ ledger: OutgoingChequeLedger, byID: [UUID: ChequeRecord],
                                   visibleIDs: Set<UUID>, selected: ChequeSelectionSummary) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                scopePicker
                listActions(visibleIDs: visibleIDs)
                if isSelecting {
                    selectionActions(visibleIDs: visibleIDs)
                    // The total scrolls with the controls so it cannot cover the whole
                    // ledger at the largest text sizes or in a short landscape window.
                    ChequeSelectionSummaryView(summary: selected)
                }
                Text(app.tr(showsPaid ? "Paid cheques" : "Postdated cheques"))
                    .font(.headline).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("outgoingTableTitle")
                ledgerRows(ledger, byID: byID)
                if ledger.rows.isEmpty { emptyLedger }
            }
            .padding(16)
        }
        .accessibilityIdentifier("outgoingChequeTable")
    }

    private var emptyLedger: some View {
        ContentUnavailableView(app.tr(showsPaid ? "No paid cheques" : "No outgoing cheques"),
                               systemImage: showsPaid ? "checkmark.circle" : "doc.text",
                               description: Text(app.tr(showsPaid
                                ? "Paid cheques appear here with their details and payment dates."
                                : "Outgoing cheques you add appear here in date order.")))
            .padding(.top, 32)
    }

    private func ledgerRows(_ ledger: OutgoingChequeLedger, byID: [UUID: ChequeRecord]) -> some View {
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
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: alignment)
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
private struct OutgoingChequeTableTitle: View {
    @Environment(AppState.self) private var app
    var showsPaidDates = false

    var body: some View {
        Text(app.tr(showsPaidDates ? "Paid cheques" : "Postdated cheques"))
            .font(.subheadline.bold())
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(OutgoingChequeStyle.title, ignoresSafeAreaEdges: [])
            .border(OutgoingChequeStyle.grid, width: 0.5)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("outgoingTableTitle")
    }
}

@MainActor
private struct OutgoingChequeTableHeader: View {
    @Environment(AppState.self) private var app
    var showsPaidDates = false
    var isSelecting = false

    var body: some View {
            HStack(spacing: 0) {
                heading("Value", span: OutgoingChequeColumn.amount)
                heading("Pay to", span: OutgoingChequeColumn.payee)
                heading("Cheque no.", span: OutgoingChequeColumn.number)
                heading("Cheque date", span: OutgoingChequeColumn.date)
                heading(isSelecting ? "Select" : (showsPaidDates ? "Payment date" : "Balance"), span: OutgoingChequeColumn.balance)
            }
            .fixedSize(horizontal: false, vertical: true)
        .background(OutgoingChequeStyle.cell, ignoresSafeAreaEdges: [])
    }

    private func heading(_ key: String, span: Int) -> some View {
        SheetCell(span: span) {
            Text(app.tr(key))
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct OutgoingChequeRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        Group {
            if dynamicTypeSize.isAccessibilitySize { accessibleFields }
            else { sheetFields }
        }
        .opacity(cancelled ? 0.55 : 1)
        .contentShape(Rectangle())
        .overlay { if isSelecting && isSelected { Rectangle().strokeBorder(Theme.accent, lineWidth: 2).allowsHitTesting(false) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibleDescription))
        .accessibilityIdentifier("cheque-row-\(cheque.id.uuidString)")
    }

    private var sheetFields: some View {
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
    }

    private var accessibleFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cheque.party.isEmpty ? app.tr("Cheque") : NumericInput.latinDigits(cheque.party))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            accessibleField("Cheque number", value: number.isEmpty ? "—" : number)
            accessibleField("Amount", value: amount + " " + cheque.currencyCode)
            accessibleField("Due date", value: date)
            accessibleField(showsPaidDates ? "Payment date" : "Balance", value: showsPaidDates ? paymentDate : balance)
            Text(statusLabel).font(.subheadline)
                .foregroundStyle(cheque.status == .returned || cheque.isOverdue(on: app.today) ? Theme.red : Theme.accent)
            if isSelecting {
                Label(app.tr(isSelected ? "Selected" : "Not selected"),
                      systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func accessibleField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(app.tr(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body).monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var amountCell: some View {
        // The bar is scaled to the largest listed amount, like the sheet's data bars.
        SheetCell(span: OutgoingChequeColumn.amount, fill: rowFill, alignment: .trailing, bar: row.barFraction) {
            numeric(amount).strikethrough(cancelled)
        }
    }

    /// Numbers keep their left-to-right order and may wrap unusually long references.
    private func numeric(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
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
