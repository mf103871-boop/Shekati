import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct ChequeListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    @State private var paperFilter: PaperState?
    @State private var filter: ChequeFilter
    @State private var showingFilters = false
    @State private var showingEditor = false
    @State private var showingReport = false
    @State private var reportCheques: [ChequeSnapshot] = []
    @State private var reportOutstanding: [ChequeSnapshot] = []
    @State private var settlingRecord: ChequeRecord?
    @State private var scopeOverride: ChequeListScope?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    init(initialFilter: ChequeFilter = .init()) {
        var initial = initialFilter
        initial.outstandingOnly = false
        _filter = State(initialValue: initial)
        _scopeOverride = State(initialValue: initialFilter.outstandingOnly || initialFilter.dateScope != .all ? .outstanding : nil)
    }

    private var hasFilters: Bool {
        paperFilter != nil || filter.direction != nil || filter.status != nil || filter.bank != nil ||
        filter.from != nil || filter.through != nil || filter.dateScope != .all
    }

    private var scope: ChequeListScope { scopeOverride ?? app.preferences.chequeListScope }

    private var effectiveFilter: ChequeFilter {
        var value = filter
        value.outstandingOnly = scope == .outstanding
        return value
    }

    var body: some View {
        // Derive the filtered/sorted rows and exact totals once for this update.
        // Deleted records remain in the global rank slots only, for safe restoration.
        let live = records.filter { $0.deletedAt == nil }
        let positions = BankingLedger.effectivePositions(records: records, events: events)
        let activeRecords = live.filter { record in
            if scope == .outstanding && positions[record.id]?.isOpen != true { return false }
            return paperFilter == nil || positions[record.id]?.state == paperFilter
        }
        let snapshots = activeRecords.map { record in
            var snapshot = record.snapshot
            if let state = positions[record.id]?.legacyStatus { snapshot.status = state }
            return snapshot
        }
        let result = ChequeListResult(cheques: snapshots, filter: effectiveFilter,
                                      sort: app.preferences.sort, ascending: app.preferences.ascending, today: app.today)
        let byID = Dictionary(activeRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visible = result.cheques.compactMap { byID[$0.id] }
        let outstanding = result.cheques.compactMap { $0.remainingObligation(using: positions[$0.id]) }
        Group {
            if dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact {
                // One scrolling surface keeps large controls from squeezing the rows.
                listContent(visible, activeCount: activeRecords.count, result: result, positions: positions, outstanding: outstanding, scrollsControls: true)
            } else {
                VStack(spacing: 0) {
                    listControls(result, outstanding: outstanding)
                    listContent(visible, activeCount: activeRecords.count, result: result, positions: positions, outstanding: outstanding, scrollsControls: false)
                }
            }
        }
            .background(Theme.background)
            .environment(\.editMode, $editMode)
            .navigationTitle(app.tr("Cheques"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query.westernDigits, prompt: Text(app.tr("Search number, name, bank or reference")))
            .toolbar {
                ChequeListToolbar(
                    canReorder: app.preferences.sort == .manual && !visible.isEmpty,
                    hasFilters: hasFilters,
                    showingFilters: $showingFilters,
                    showingEditor: $showingEditor,
                    editMode: $editMode,
                    clearFilters: { filter = .init(query: filter.query); paperFilter = nil },
                    showReport: {
                        reportCheques = result.cheques
                        reportOutstanding = outstanding
                        showingReport = true
                    },
                    canReport: !visible.isEmpty
                )
            }
            .onChange(of: app.preferences.sort) { _, sort in
                if sort != .manual { editMode = .inactive }
            }
            .onChange(of: filter.direction) { _, _ in editMode = .inactive }
            .sheet(isPresented: $showingEditor) {
                NavigationStack {
                    ChequeEditorView()
                        .environment(\.locale, app.preferences.language.locale)
                        .environment(\.layoutDirection, sheetDirection)
                }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, sheetDirection)
            }
            .sheet(isPresented: $showingFilters) {
                NavigationStack {
                    ChequeFilterSheet(initial: effectiveFilter, banks: activeRecords.map(\.bank)) { selected in
                        setScope(selected.outstandingOnly ? .outstanding : .allRecords)
                        filter = selected
                        filter.outstandingOnly = false
                    }
                        .environment(\.locale, app.preferences.language.locale)
                        .environment(\.layoutDirection, sheetDirection)
                }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, sheetDirection)
            }
            .sheet(item: $settlingRecord) { ChequeSettlementSheet(record: $0) }
            .sheet(isPresented: $showingReport) {
                NavigationStack {
                    ChequeReportSheet(cheques: reportCheques, outstanding: reportOutstanding)
                        .environment(\.locale, app.preferences.language.locale)
                        .environment(\.layoutDirection, sheetDirection)
                }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, sheetDirection)
            }
            .alert(app.tr("Could not save changes"), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(app.tr("OK"), role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private var sheetDirection: LayoutDirection {
        app.preferences.language.isRTL ? .rightToLeft : .leftToRight
    }

    private func listControls(_ result: ChequeListResult, outstanding: [ChequeSnapshot]) -> some View {
        VStack(spacing: 0) {
            HStack {
                scopePicker
                Menu {
                    Button(app.tr("All")) { paperFilter = nil }
                    ForEach(PaperState.allCases, id: \.rawValue) { state in
                        Button(app.tr(state.title)) { paperFilter = state; setScope(.allRecords) }
                    }
                } label: {
                    Label(app.tr(paperFilter?.title ?? "Status"), systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            directionPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            periodChips
                .padding(.bottom, 10)
            if hasFilters || !filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(app.tr("Clear search and filters")) {
                    filter = .init()
                    paperFilter = nil
                    editMode = .inactive
                }
                // Keep this action independent of the other controls in the List row.
                .buttonStyle(.borderless)
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("clearActiveFilters")
            }
            shownSummary(result, outstanding: outstanding)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

        }
    }

    private func listContent(_ visible: [ChequeRecord], activeCount: Int, result: ChequeListResult,
                             positions: [UUID: ChequePosition], outstanding: [ChequeSnapshot], scrollsControls: Bool) -> some View {
        List {
            if scrollsControls {
                // An ordinary row (not a pinned Section header) is outside the movable ForEach.
                listControls(result, outstanding: outstanding)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
            }
            ForEach(visible) { record in
                rowLink(record, position: positions[record.id])
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.background)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .moveDisabled(app.preferences.sort != .manual)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if positions[record.id]?.isOpen == true {
                        Button {
                            settlingRecord = record
                        } label: {
                            Label(app.tr("Cheque actions"), systemImage: "checkmark.circle")
                        }
                        .tint(Theme.accent)
                        .accessibilityIdentifier("settleCheque-\(record.id.uuidString)")
                    }
                }
            }
            .onMove { source, destination in
                guard app.preferences.sort == .manual else { return }
                move(visibleIDs: visible.map(\.id), from: source, to: destination)
            }
            if scrollsControls && visible.isEmpty {
                emptyContent(activeCount: activeCount)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
            }
        }
        // Recreate the native list after a direction change without resetting the filter state.
        .id(app.preferences.language.rawValue)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if !scrollsControls && visible.isEmpty {
                emptyContent(activeCount: activeCount)
                .padding(28)
            }
        }
    }

    private func emptyContent(activeCount: Int) -> some View {
        VStack(spacing: 18) {
            EmptyStateView(
                title: app.tr(activeCount == 0 ? "No cheques yet" : "No matching cheques"),
                message: app.tr(activeCount == 0 ? "Add your first cheque to keep its details and reminders together." : "Try another search or clear the filters."),
                systemImage: activeCount == 0 ? "doc.text" : "line.3.horizontal.decrease.circle"
            )
            if activeCount == 0 {
                Button(app.tr("Add cheque")) { showingEditor = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.currencyCode.isEmpty)
            } else {
                Button(app.tr("Clear search and filters")) { filter = .init(); paperFilter = nil }
                    .buttonStyle(.bordered)
                if scope == .outstanding {
                    Button(app.tr("Show all and history")) {
                        filter = .init()
                paperFilter = nil
                        setScope(.allRecords)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("showHistoryFromEmptyList")
                }
            }
        }
    }

    @ViewBuilder
    private func rowLink(_ record: ChequeRecord, position: ChequePosition?) -> some View {
        if position?.isOpen == true {
            detailLink(record, position: position)
                .accessibilityAction(named: Text(app.tr("Cheque actions"))) {
                    settlingRecord = record
                }
        } else { detailLink(record, position: position) }
    }

    private func detailLink(_ record: ChequeRecord, position: ChequePosition?) -> some View {
        NavigationLink { ChequeDetailView(record: record) } label: { ChequeRowView(record: record, position: position, needsReview: position == nil) }
    }

    private func setScope(_ value: ChequeListScope) {
        scopeOverride = value
        app.preferences.chequeListScope = value
        editMode = .inactive
    }

    @ViewBuilder
    private var scopePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            scopeSelection.pickerStyle(.menu)
        } else { scopeSelection.pickerStyle(.segmented) }
    }

    private var scopeSelection: some View {
        Picker(app.tr("Show cheques"), selection: Binding(get: { scope }, set: { setScope($0) })) {
            Text(app.tr("Outstanding")).tag(ChequeListScope.outstanding)
            Text(app.tr("All and history")).tag(ChequeListScope.allRecords)
        }
        .accessibilityIdentifier("chequeHistoryScopePicker")
    }

    private var periodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodChip("All dates", scope: .all)
                periodChip("Today", scope: .today)
                periodChip("Next 7 days", scope: .upcoming)
                periodChip("Overdue", scope: .overdue)
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("chequePeriodChips")
    }

    private func periodChip(_ title: String, scope dateScope: ChequeDateScope) -> some View {
        let selected = filter.dateScope == dateScope
        return Button {
            filter.dateScope = dateScope
            if dateScope != .all { setScope(.outstanding) }
            editMode = .inactive
        } label: {
            Text(app.tr(title)).font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("period-\(dateScope.rawValue)")
    }

    @ViewBuilder
    private var directionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            directionSelection.pickerStyle(.menu)
        } else {
            directionSelection.pickerStyle(.segmented)
        }
    }

    private var directionSelection: some View {
        Picker(app.tr("Direction"), selection: $filter.direction) {
            Text(app.tr("All")).tag(nil as ChequeDirection?)
            Text(app.tr("Incoming")).tag(ChequeDirection.incoming as ChequeDirection?)
            Text(app.tr("Outgoing")).tag(ChequeDirection.outgoing as ChequeDirection?)
        }
        .accessibilityIdentifier("listDirectionPicker")
    }

    private func shownSummary(_ result: ChequeListResult, outstanding: [ChequeSnapshot]) -> some View {
        let groups = Dictionary(grouping: outstanding, by: \.currencyCode)
        return VStack(alignment: .leading, spacing: 8) {
            shownCount(result.cheques.count)
            ForEach(groups.keys.sorted(), id: \.self) { code in
                let totals = ChequeDirectionTotals(cheques: groups[code] ?? [])
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        directionTotal(.incoming, totals: totals, currency: code)
                        Spacer(minLength: 8)
                        directionTotal(.outgoing, totals: totals, currency: code)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        directionTotal(.incoming, totals: totals, currency: code)
                        directionTotal(.outgoing, totals: totals, currency: code)
                    }
                }
            }
        }
    }

    private func shownCount(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(DisplayFormatting.count(count, locale: app.preferences.language.locale))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(app.tr("Shown cheques")).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shownChequeCount")
    }

    private func directionTotal(_ direction: ChequeDirection, totals: ChequeDirectionTotals, currency: String) -> some View {
        let total = direction == .incoming ? totals.incomingMinorUnits : totals.outgoingMinorUnits
        return VStack(alignment: .leading, spacing: 3) {
            Text(app.tr(direction == .incoming ? "Incoming" : "Outgoing") + " · " + app.tr("Remaining"))
                .font(.footnote).foregroundStyle(.secondary)
            if let total {
                ReadableCurrencyAmount(minorUnits: total, currencyCode: currency, formatted: DisplayFormatting.amount(minorUnits: total, currencyCode: currency, locale: app.preferences.language.locale)).font(.subheadline.weight(.semibold))
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(app.tr("Total exceeds supported range")).font(.footnote).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(direction == .incoming ? "shownIncomingAmount" : "shownOutgoingAmount")
    }

    private func move(visibleIDs: [UUID], from source: IndexSet, to destination: Int) {
        let global = ChequeListEngine.filteredAndSorted(
            cheques: records.map(\.snapshot), filter: .init(), sort: .manual,
            ascending: app.preferences.ascending
        ).map(\.id)
        let ordered = ChequeListEngine.reorderedIDs(
            all: global, visible: visibleIDs, from: source, to: destination
        )
        // Identifiers can repeat after the same backup is restored on two devices before they sync; never trap.
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in ordered.enumerated() {
            let rank = app.preferences.ascending ? Int64(index) : Int64(ordered.count - index)
            if byID[id]?.manualRank != rank { byID[id]?.manualRank = rank }
        }
        do {
            try context.save()
            app.didMutate()
        } catch {
            context.rollback()
            errorMessage = app.tr("Your previous order was kept. Please try again.")
        }
    }

}

/// A concrete toolbar type keeps the deprecated View-producing toolbar overload out of inference.
@MainActor
private struct ChequeListToolbar: ToolbarContent {
    @Environment(AppState.self) private var app
    let canReorder: Bool
    let hasFilters: Bool
    @Binding var showingFilters: Bool
    @Binding var showingEditor: Bool
    @Binding var editMode: EditMode
    let clearFilters: () -> Void
    let showReport: () -> Void
    let canReport: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingEditor = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").accessibilityHidden(true)
                    Text(app.tr("Add"))
                }
            }
                .accessibilityLabel(app.tr("Add cheque"))
                .disabled(app.currencyCode.isEmpty)
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button(action: showReport) {
                Label(app.tr("Export this list as PDF"), systemImage: "square.and.arrow.up")
            }
            .disabled(!canReport)
            .accessibilityIdentifier("exportVisibleChequeReport")
            Divider()
            Button {
                editMode = .inactive
                showingFilters = true
            } label: {
                Label(app.tr("Filters"), systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            if hasFilters {
                Button(app.tr("Clear filters")) {
                    editMode = .inactive
                    clearFilters()
                }
            }
            Divider()
            Picker(app.tr("Sort by"), selection: Binding(
                get: { app.preferences.sort }, set: { app.preferences.sort = $0 }
            )) {
                ForEach(ChequeSort.allCases, id: \.self) { sort in
                    Text(app.tr(sortTitle(sort))).tag(sort)
                }
            }
            Picker(app.tr("Order"), selection: Binding(
                get: { app.preferences.ascending }, set: { app.preferences.ascending = $0 }
            )) {
                Text(app.tr("Ascending")).tag(true)
                Text(app.tr("Descending")).tag(false)
            }
            if canReorder {
                Divider()
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Label(app.tr(editMode.isEditing ? "Done" : "Reorder cheques"), systemImage: "arrow.up.arrow.down")
                }
                .accessibilityHint(app.tr("Drag cheques to change their order."))
            }
        } label: {
            Text(app.tr("Filters and sort"))
        }
        .accessibilityLabel(app.tr("Filters and sort"))
    }

    private func sortTitle(_ sort: ChequeSort) -> String {
        switch sort {
        case .dueDate: return "Due date"
        case .amount: return "Amount"
        case .name: return "Name"
        case .status: return "Status"
        case .createdAt: return "Date added"
        case .manual: return "My order"
        }
    }
}

@MainActor
private struct ChequeFilterSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChequeFilter
    @State private var invalidRange = false
    let banks: [String]
    let apply: (ChequeFilter) -> Void

    init(initial: ChequeFilter, banks: [String], apply: @escaping (ChequeFilter) -> Void) {
        _draft = State(initialValue: initial)
        self.banks = banks
        self.apply = apply
    }

    private var bankChoices: [String] {
        var choices = Set(banks.filter { !$0.isEmpty })
        if let selected = draft.bank { choices.insert(selected) }
        return choices.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                Toggle(app.tr("Outstanding only"), isOn: $draft.outstandingOnly)
                Picker(app.tr("Direction"), selection: $draft.direction) {
                    Text(app.tr("All")).tag(nil as ChequeDirection?)
                    Text(app.tr("Incoming")).tag(ChequeDirection.incoming as ChequeDirection?)
                    Text(app.tr("Outgoing")).tag(ChequeDirection.outgoing as ChequeDirection?)
                }
                Picker(app.tr("Status"), selection: $draft.status) {
                    Text(app.tr("All")).tag(nil as ChequeStatus?)
                    ForEach(ChequeStatus.allCases, id: \.self) { status in
                        Text(app.tr(statusTitle(status))).tag(status as ChequeStatus?)
                    }
                }
                Picker(app.tr("Bank"), selection: $draft.bank) {
                    Text(app.tr("All banks")).tag(nil as String?)
                    ForEach(bankChoices, id: \.self) { Text($0).tag($0 as String?) }
                }
            }
            Section(app.tr("Due date")) {
                Picker(app.tr("Period"), selection: $draft.dateScope) {
                    Text(app.tr("All dates")).tag(ChequeDateScope.all)
                    Text(app.tr("Due today")).tag(ChequeDateScope.today)
                    Text(app.tr("Next 7 days")).tag(ChequeDateScope.upcoming)
                    Text(app.tr("Overdue")).tag(ChequeDateScope.overdue)
                }
                Toggle(app.tr("From date"), isOn: Binding(
                    get: { draft.from != nil }, set: { draft.from = $0 ? .today : nil }
                ))
                if draft.from != nil {
                    DatePicker(app.tr("From"), selection: Binding(
                        get: { (draft.from ?? .today).date() },
                        set: { draft.from = LocalDay(date: $0) }
                    ), displayedComponents: .date)
                        .environment(\.locale, app.preferences.language.locale)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                }
                Toggle(app.tr("Through date"), isOn: Binding(
                    get: { draft.through != nil }, set: { draft.through = $0 ? .today : nil }
                ))
                if draft.through != nil {
                    DatePicker(app.tr("Through"), selection: Binding(
                        get: { (draft.through ?? .today).date() },
                        set: { draft.through = LocalDay(date: $0) }
                    ), displayedComponents: .date)
                        .environment(\.locale, app.preferences.language.locale)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                }
            }
        }
        .navigationTitle(app.tr("Filters"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(app.tr("Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(app.tr("Apply")) {
                    if let from = draft.from, let through = draft.through, from > through {
                        invalidRange = true
                    } else {
                        apply(draft)
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(app.tr("Clear filters")) { draft = .init(query: draft.query) }
            }
        }
        .alert(app.tr("Check the date range"), isPresented: $invalidRange) {
            Button(app.tr("OK"), role: .cancel) { }
        } message: {
            Text(app.tr("The end date must be on or after the start date."))
        }
    }

    private func statusTitle(_ status: ChequeStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .settled: return "Settled"
        case .returned: return "Returned"
        case .cancelled: return "Cancelled"
        }
    }
}
