import SwiftUI
import SwiftData
import ShekatiCore

/// Computed from the entire journal so a filtered view cannot turn an unresolved branch into a payable.
@MainActor
struct ChequeAudit {
    let positions: [UUID: ChequePosition]
    let disputed: Set<UUID>
    init(records: [ChequeRecord], events: [LedgerEventRecord]) {
        let effective = BankingLedger.effectivePositions(records: records, events: events)
        let byID = Dictionary(grouping: records, by: \.id)
        let touched = Set(events.compactMap(\.chequeID))
        var unresolved = Set(effective.compactMap { $0.value.conflicts.isEmpty ? nil : $0.key })
        for (id, group) in byID where group.count > 1 || (effective[id] == nil && touched.contains(id)) {
            unresolved.insert(id)
        }
        for event in events where event.operation == nil {
            if let id = event.chequeID { unresolved.insert(id) }
        }
        positions = effective
        disputed = unresolved
    }
}

@MainActor
struct UnverifiedCurrencyTotal: View {
    @Environment(AppState.self) private var app
    let currency: String
    var body: some View {
        Label(app.tr("Total unavailable") + " · " + currency + " · " + app.tr("Review conflicting entries"),
              systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium)).foregroundStyle(.orange)
            .accessibilityIdentifier("uncertainTotal-" + currency)
    }
}

extension ChequeSnapshot {
    func remainingObligation(using position: ChequePosition?) -> Self? {
        guard let position, position.conflicts.isEmpty, position.isOpen, position.state != .draft, position.state != .endorsed,
              position.remaining > 0 else { return nil }
        var row = self
        row.amountMinorUnits = position.remaining
        row.status = position.legacyStatus
        return row
    }
}

@MainActor
struct AmountPrivacyButton: View {
    @Environment(AppState.self) private var app
    @AppStorage("shekati.hideAmounts") private var hidden = false
    var body: some View {
        Button { hidden.toggle() } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(app.tr(hidden ? "Show amounts" : "Hide amounts"))
    }
}

@MainActor
struct ShekatiMoreView: View {
    @Environment(AppState.self) private var app
    @EnvironmentObject private var plus: ShekatiPlusStore
    @AppStorage("shekati.hideAmounts") private var hidden = false
    var body: some View {
        List {
            Section {
                NavigationLink { BankingAccountsView(isPlus: plus.isPlus) } label: {
                    Label(app.tr("Bank accounts"), systemImage: "building.columns")
                }
                NavigationLink { PartyDirectoryView() } label: {
                    Label(app.tr("Contacts"), systemImage: "person.2")
                }
                if !hidden {
                    NavigationLink { OutgoingChequeTableView() } label: {
                        Label(app.tr("Outgoing cheque ledger"), systemImage: "tablecells")
                    }.accessibilityIdentifier("outgoingLedgerLink")
                }
            }
            Section {
                NavigationLink { ShekatiPlusView() } label: {
                    Label(app.tr("Shekati Plus"), systemImage: "star.circle")
                }.accessibilityIdentifier("moreSubscriptionLink")
                NavigationLink { BankingCalendarSettingsView() } label: {
                    Label(app.tr("Banking calendar"), systemImage: "calendar.badge.clock")
                }
                NavigationLink { DataToolsView() } label: {
                    Label(app.tr("Data and backup"), systemImage: "archivebox")
                }
                NavigationLink { SettingsView() } label: {
                    Label(app.tr("Settings"), systemImage: "gearshape")
                }.accessibilityIdentifier("moreSettingsLink")
            }
        }.navigationTitle(app.tr("More"))
    }
}

@MainActor
private struct PartyDirectoryView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @State private var query = ""
    private var groups: [String: [ChequeRecord]] {
        Dictionary(grouping: records.filter { $0.deletedAt == nil && !$0.party.isEmpty }, by: { $0.party })
    }
    var body: some View {
        List {
            ForEach(groups.keys.filter { query.isEmpty || $0.localizedStandardContains(query) }
                .sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }), id: \.self) { party in
                NavigationLink(party) {
                    List((groups[party] ?? []).sorted { $0.dueDate < $1.dueDate }) { record in
                        NavigationLink { ChequeDetailView(record: record) } label: { ChequeRowView(record: record) }
                    }.navigationTitle(party)
                }
            }
        }.navigationTitle(app.tr("Contacts")).searchable(text: $query, prompt: app.tr("Name"))
    }
}

@MainActor
struct DueCalendarView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    @State private var selected = Date()
    @State private var month = Date()
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = app.preferences.language.locale
        result.timeZone = TimeZone(identifier: app.preferences.bankingCalendar.timeZoneID) ?? .current
        var regionCalendar = Calendar(identifier: .gregorian)
        regionCalendar.locale = Locale(identifier: "en_" + app.preferences.bankingCalendar.region)
        result.firstWeekday = regionCalendar.firstWeekday
        return result
    }
    private var start: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }
    private var days: [Date] {
        (calendar.range(of: .day, in: .month, for: start) ?? 1..<29).compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }
    }
    private func dayRecords(from records: [ChequeRecord]) -> [ChequeRecord] {
        records.filter { $0.dueDate == LocalDay(date: selected, calendar: calendar) }.sorted { ($0.number, $0.party) < ($1.number, $1.party) }
    }

    var body: some View {
        let audit = ChequeAudit(records: records, events: events)
        let positions = audit.positions
        let validRecords = records.filter { $0.isActive && (positions[$0.id] != nil || audit.disputed.contains($0.id)) }
        let dayRecords = self.dayRecords(from: validRecords)
        let grouped = Dictionary(grouping: validRecords, by: { $0.dueDateISO })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }
                        .accessibilityLabel(app.tr("Previous month"))
                    Spacer()
                    Text(start.formatted(.dateTime.month(.wide).year().locale(app.preferences.language.locale)))
                        .font(.headline)
                    Spacer()
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }
                        .accessibilityLabel(app.tr("Next month")).accessibilityIdentifier("calendarNextMonth")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 1) }
                    ForEach(days, id: \.self) { day in
                        let entries = grouped[LocalDay(date: day, calendar: calendar).iso] ?? []
                        dayButton(day, entries: entries, positions: positions)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(app.formatDay(LocalDay(date: selected, calendar: calendar))).font(.headline)
                    if let closure = closedDayLabel(selected) {
                        Label(app.tr(closure), systemImage: "calendar.badge.minus").font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(countSummary(dayRecords, positions: positions))
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("selectedDayCounts")
                    if dayRecords.isEmpty {
                        Text(app.tr("No cheques due on this day")).foregroundStyle(.secondary)
                    } else {
                        let disputedCodes = Set(dayRecords.filter { audit.disputed.contains($0.id) }.map(\.currencyCode))
                        ForEach(disputedCodes.sorted(), id: \.self) { code in UnverifiedCurrencyTotal(currency: code) }
                        ForEach(ChequeDirection.allCases, id: \.self) { direction in
                            let items = dayRecords.filter { $0.direction == direction && !disputedCodes.contains($0.currencyCode) }
                            ForEach(Array(Set(items.map(\.currencyCode))).sorted(), id: \.self) { code in
                                let total = ChequeDirectionTotals(cheques: items.filter { $0.currencyCode == code }.compactMap { $0.snapshot.remainingObligation(using: positions[$0.id]) })
                                let minor = direction == .incoming ? total.incomingMinorUnits : total.outgoingMinorUnits
                                if let minor {
                                    ResponsiveValueRow(title: app.tr(direction == .incoming ? "Incoming" : "Outgoing") + " · " + app.tr("Remaining"),
                                                       value: hidesAmounts ? "••••" : DisplayFormatting.amount(minorUnits: minor, currencyCode: code, locale: app.preferences.language.locale))
                                }
                            }
                        }
                        ForEach(dayRecords) { record in
                            NavigationLink { ChequeDetailView(record: record) } label: {
                                ChequeRowView(record: record, position: positions[record.id], needsReview: audit.disputed.contains(record.id)).padding(.horizontal, 14)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityIdentifier("cheque-row-" + record.id.uuidString)
                        }
                    }
                }.padding(.horizontal, 8)
            }.padding(.horizontal, 8).padding(.bottom)
        }.background(Theme.background).navigationTitle(app.tr("Calendar"))
    }

    private func closedDayLabel(_ date: Date) -> String? {
        let banking = app.preferences.bankingCalendar
        let local = LocalDay(date: date, calendar: calendar)
        if banking.holidays.contains(local.iso) { return "Holiday" }
        return banking.closedWeekdays.contains(calendar.component(.weekday, from: date)) ? "Weekly closing days" : nil
    }

    private func countSummary(_ entries: [ChequeRecord], positions: [UUID: ChequePosition]) -> String {
        let counts = [("Incoming", entries.filter { $0.direction == .incoming }.count),
                      ("Outgoing", entries.filter { $0.direction == .outgoing }.count),
                      ("Returned", entries.filter { positions[$0.id]?.state == .returned }.count)]
        return counts.map { app.tr($0.0) + " " + DisplayFormatting.count($0.1, locale: app.preferences.language.locale) }
            .joined(separator: " · ")
    }

    private func dayButton(_ day: Date, entries: [ChequeRecord], positions: [UUID: ChequePosition]) -> some View {
        let closure = closedDayLabel(day)
        let current = calendar.isDate(day, inSameDayAs: selected)
        return Button { selected = day } label: {
            VStack(spacing: 3) {
                HStack(spacing: 1) {
                    Text(String(calendar.component(.day, from: day))).font(.subheadline)
                    if closure != nil {
                        Image(systemName: "minus.circle").font(.caption2).accessibilityHidden(true)
                    }
                }
                HStack(spacing: 2) {
                    if entries.contains(where: { $0.direction == .incoming }) { Circle().fill(Theme.incoming) }
                    if entries.contains(where: { $0.direction == .outgoing }) { Circle().fill(Theme.outgoing) }
                    if entries.contains(where: { positions[$0.id]?.state == .returned }) { Circle().fill(Color.orange) }
                }.frame(width: 20, height: 5)
            }.frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(current ? Color.white : .primary)
                .background(current ? Theme.brandBackground : closure != nil ? Color.orange.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("dueDay-" + LocalDay(date: day, calendar: calendar).iso)
            .accessibilityLabel(app.formatDay(LocalDay(date: day, calendar: calendar)))
            .accessibilityValue(([closure.map { app.tr($0) }, countSummary(entries, positions: positions)] as [String?]).compactMap { $0 }.joined(separator: " · "))
            .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: start) else { return }
        month = next
        selected = next
    }
}
