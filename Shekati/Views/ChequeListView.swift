import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct ChequeListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var records: [ChequeRecord]
    @State private var filter: ChequeFilter
    @State private var showingFilters = false
    @State private var showingEditor = false
    @State private var errorMessage: String?

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
        listContent
            .toolbar {
                ChequeListToolbar(
                    canReorder: app.preferences.sort == .manual && !visible.isEmpty,
                    hasFilters: hasFilters,
                    showingFilters: $showingFilters,
                    showingEditor: $showingEditor
                )
            }
            .sheet(isPresented: $showingEditor) {
                NavigationStack { ChequeEditorView() }
            }
            .sheet(isPresented: $showingFilters) {
                NavigationStack {
                    ChequeFilterSheet(initial: filter, banks: records.map(\.bank)) { filter = $0 }
                }
            }
            .alert(app.tr("Could not save changes"), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(app.tr("OK"), role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private var listContent: some View {
        List {
            if !visible.isEmpty {
                HStack {
                    if !app.currencyConflict && !app.currencyCode.isEmpty {
                      VStack(alignment: .leading, spacing: 5) {
                        Text(app.tr("Shown amount")).font(.caption).foregroundStyle(.secondary)
                        if let total = shownTotal {
                            AmountText(minorUnits: total).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        } else {
                            Text(app.tr("Total exceeds supported range")).font(.footnote).foregroundStyle(.orange)
                        }
                      }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(app.tr("Cheques")).font(.caption).foregroundStyle(.secondary)
                        Text(visible.count, format: .number).font(.title3.bold()).monospacedDigit()
                    }
                }
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            }
            ForEach(visible, id: \.id) { record in
                NavigationLink {
                    ChequeDetailView(record: record)
                } label: {
                    ChequeRowView(record: record)
                }
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        .navigationTitle(app.tr("Cheques"))
        .searchable(text: $filter.query, prompt: Text(app.tr("Search number, bank or name")))
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

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if canReorder {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().accessibilityHint(app.tr("Drag cheques to change their order."))
            }
        }
        ToolbarItem(placement: .topBarTrailing) { sortMenu }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingFilters = true } label: {
                Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(app.tr("Filters"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingEditor = true } label: { Image(systemName: "plus") }
                .accessibilityLabel(app.tr("Add cheque"))
                .disabled(app.currencyConflict || app.currencyCode.isEmpty)
        }
    }

    private var sortMenu: some View {
        Menu {
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
        } label: { Image(systemName: "arrow.up.arrow.down") }
        .accessibilityLabel(app.tr("Sort cheques"))
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
