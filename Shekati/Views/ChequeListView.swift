import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct ChequeListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var records: [ChequeRecord]
    @State private var filter: ChequeFilter
    @State private var showingFilters = false
    @State private var showingEditor = false
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    init(initialFilter: ChequeFilter = .init()) {
        _filter = State(initialValue: initialFilter)
    }

    private var visible: [ChequeRecord] {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return ChequeListEngine.filteredAndSorted(
            cheques: records.map(\.snapshot), filter: filter,
            sort: app.preferences.sort, ascending: app.preferences.ascending, today: app.today
        ).compactMap { byID[$0.id] }
    }

    private var hasFilters: Bool {
        filter.direction != nil || filter.status != nil || filter.bank != nil ||
        filter.from != nil || filter.through != nil || filter.dateScope != .all || filter.outstandingOnly
    }

    private var shownTotal: Int64? {
        var total: Int64 = 0
        for record in visible {
            let result = total.addingReportingOverflow(record.amountMinorUnits)
            if result.overflow { return nil }
            total = result.partialValue
        }
        return total
    }

    var body: some View {
        VStack(spacing: 0) {
            directionPicker
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            shownSummary
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            if !visible.isEmpty {
                ChequeTableHeaderView()
                    .accessibilityIdentifier("chequeTableHeader")
                    .padding(.leading, 16)
                    // Match the row's content inset and the native disclosure indicator.
                    .padding(.trailing, 36)
                    .padding(.vertical, 9)
                    .background(Theme.surface)
                Divider()
            }
            listContent
        }
            .background(Theme.background)
            .environment(\.editMode, $editMode)
            .navigationTitle(app.tr("Cheques"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query, prompt: Text(app.tr("Search number, bank or name")))
            .toolbar {
                ChequeListToolbar(
                    canReorder: app.preferences.sort == .manual && !visible.isEmpty,
                    hasFilters: hasFilters,
                    showingFilters: $showingFilters,
                    showingEditor: $showingEditor,
                    editMode: $editMode,
                    clearFilters: { filter = .init(query: filter.query) }
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
                    ChequeFilterSheet(initial: filter, banks: records.map(\.bank)) { filter = $0 }
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
        app.preferences.language == .arabic ? .rightToLeft : .leftToRight
    }

    private var listContent: some View {
        List {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                NavigationLink {
                    ChequeDetailView(record: record)
                } label: {
                    ChequeRowView(record: record)
                }
                .listRowSeparator(.visible)
                .listRowSeparatorTint(Color.primary.opacity(0.1))
                .listRowBackground(index.isMultiple(of: 2) ? Theme.surface : Theme.accent.opacity(0.035))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .moveDisabled(app.preferences.sort != .manual)
            }
            .onMove { source, destination in
                guard app.preferences.sort == .manual else { return }
                move(from: source, to: destination)
            }
        }
        // Recreate the native list after a direction change without resetting the filter state.
        .id(app.preferences.language.rawValue)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if visible.isEmpty {
                VStack(spacing: 18) {
                    EmptyStateView(
                        title: app.tr(records.isEmpty ? "No cheques yet" : "No matching cheques"),
                        message: app.tr(records.isEmpty ? "Add your first cheque to keep its details and reminders together." : "Try another search or clear the filters."),
                        systemImage: records.isEmpty ? "doc.text" : "line.3.horizontal.decrease.circle"
                    )
                    if records.isEmpty {
                        Button(app.tr("Add cheque")) { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(app.currencyConflict || app.currencyCode.isEmpty)
                    } else {
                        Button(app.tr("Clear search and filters")) { filter = .init() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(28)
            }
        }
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

    private var shownSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                shownCount
                Spacer(minLength: 8)
                shownAmount.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                shownCount
                shownAmount.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shownCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(visible.count, format: .number).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(app.tr("Shown cheques")).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shownChequeCount")
    }

    @ViewBuilder
    private var shownAmount: some View {
        if !app.currencyConflict && !app.currencyCode.isEmpty {
            VStack(alignment: .trailing, spacing: 3) {
                Text(app.tr("Shown amount")).font(.footnote).foregroundStyle(.secondary)
                if let total = shownTotal {
                    AmountText(minorUnits: total).font(.subheadline.weight(.semibold))
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Text(app.tr("Total exceeds supported range")).font(.footnote).foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shownChequeAmount")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let global = ChequeListEngine.filteredAndSorted(
            cheques: records.map(\.snapshot), filter: .init(), sort: .manual,
            ascending: app.preferences.ascending
        ).map(\.id)
        let ordered = ChequeListEngine.reorderedIDs(
            all: global, visible: visible.map(\.id), from: source, to: destination
        )
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for (index, id) in ordered.enumerated() {
            byID[id]?.manualRank = app.preferences.ascending ? Int64(index) : Int64(ordered.count - index)
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
                .disabled(app.currencyConflict || app.currencyCode.isEmpty)
        }
    }

    private var optionsMenu: some View {
        Menu {
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
                }
                Toggle(app.tr("Through date"), isOn: Binding(
                    get: { draft.through != nil }, set: { draft.through = $0 ? .today : nil }
                ))
                if draft.through != nil {
                    DatePicker(app.tr("Through"), selection: Binding(
                        get: { (draft.through ?? .today).date() },
                        set: { draft.through = LocalDay(date: $0) }
                    ), displayedComponents: .date)
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
