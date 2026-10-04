import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var records: [ChequeRecord]
    @State private var showingEditor = false

    private var metrics: DashboardMetrics {
        DashboardMetrics(cheques: records.map(\.snapshot), today: app.today)
    }

    private var upcoming: [ChequeRecord] {
        records.filter { $0.snapshot.isOutstanding }.sorted {
            $0.dueDate == $1.dueDate ? $0.id.uuidString < $1.id.uuidString : $0.dueDate < $1.dueDate
        }.prefix(4).map { $0 }
    }

    var body: some View {
        let summary = metrics
        let nextCheques = upcoming
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { showingEditor = true } label: {
                    Text(app.tr("Add cheque"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.currencyConflict || app.currencyCode.isEmpty)
                .accessibilityIdentifier("addCheque")

                VStack(alignment: .leading, spacing: 8) {
                    Text(app.tr("Outstanding cheques"))
                        .font(.headline).foregroundStyle(Theme.navy)
                    VStack(spacing: 0) {
                        totalRow(.incoming, metrics: summary)
                        Divider().padding(.horizontal, 14)
                        totalRow(.outgoing, metrics: summary)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

                    if app.currencyConflict {
                        notice(
                            title: app.tr("Different currencies found"),
                            message: app.tr("Records from another device use a different currency. Resolve these records before adding new cheques. Totals are hidden to avoid mixing currencies.")
                        )
                    } else if summary.hasAmountOverflow {
                        notice(
                            title: app.tr("Total exceeds supported range"),
                            message: app.tr("View individual cheque amounts. Totals cannot be displayed accurately for these records.")
                        )
                    }
                }

                VStack(spacing: 0) {
                    dateRow("Due today", count: summary.todayCount, scope: .today)
                    Divider().padding(.horizontal, 14)
                    dateRow("Within 7 days", count: summary.upcomingCount, scope: .upcoming)
                    Divider().padding(.horizontal, 14)
                    dateRow("Overdue", count: summary.overdueCount, scope: .overdue)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

                if app.notifications.isDenied {
                    NavigationLink { SettingsView() } label: {
                        notice(
                            title: app.tr("Notifications are off"),
                            message: app.tr("Enable notifications in Settings so your scheduled reminders can appear.")
                        )
                    }
                    .buttonStyle(.plain)
                }
                if app.notifications.authorizationStatus != .notDetermined,
                   !app.notifications.isDenied, let uncovered = app.notifications.firstUncoveredDate {
                    notice(
                        title: app.tr("Refresh upcoming reminders"),
                        message: app.tr("Open the app before") + " " + app.formatDay(LocalDay(date: uncovered)) +
                            ". " + app.tr("Some later reminders still need scheduling.")
                    )
                }
                if let message = app.persistenceMessage {
                    notice(title: app.tr("Could not save changes."), message: message)
                }

                if nextCheques.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.tr(records.isEmpty ? "No cheques yet" : "No outstanding cheques"))
                            .font(.subheadline.weight(.medium))
                        if records.isEmpty {
                            Text(app.tr("Add a cheque to keep its dates and reminders here."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(app.tr("Next cheques"))
                                .font(.headline).foregroundStyle(Theme.navy)
                            Spacer(minLength: 12)
                            NavigationLink { ChequeListView() } label: {
                                Text(app.tr("See all")).font(.subheadline)
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(nextCheques) { record in
                                NavigationLink { ChequeDetailView(record: record) } label: {
                                    ChequeRowView(record: record)
                                        .padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain)
                                if record.id != nextCheques.last?.id {
                                    Divider().padding(.horizontal, 14)
                                }
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(app.tr("Shekati"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                ChequeEditorView()
                    .environment(\.locale, app.preferences.language.locale)
                    .environment(\.layoutDirection, sheetDirection)
            }
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, sheetDirection)
        }
    }

    private var sheetDirection: LayoutDirection {
        app.preferences.language == .arabic ? .rightToLeft : .leftToRight
    }

    private func totalRow(_ direction: ChequeDirection, metrics: DashboardMetrics) -> some View {
        NavigationLink {
            ChequeListView(initialFilter: ChequeFilter(direction: direction, outstandingOnly: true))
        } label: {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        totalLabel(direction)
                        totalValue(direction, metrics: metrics)
                    }
                    Spacer(minLength: 0)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            totalLabel(direction).fixedSize()
                            Spacer(minLength: 12)
                            totalValue(direction, metrics: metrics).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            totalLabel(direction)
                            totalValue(direction, metrics: metrics)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Image(systemName: "chevron.forward")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private func totalLabel(_ direction: ChequeDirection) -> some View {
        Text(app.tr(direction == .incoming ? "To collect" : "To pay"))
            .font(.body).foregroundStyle(.primary)
    }

    @ViewBuilder
    private func totalValue(_ direction: ChequeDirection, metrics: DashboardMetrics) -> some View {
        if !app.currencyConflict && !app.currencyCode.isEmpty && !metrics.hasAmountOverflow {
            Text(app.formatAmount(direction == .incoming ? metrics.incomingMinorUnits : metrics.outgoingMinorUnits))
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.navy)
        } else {
            Text("—").font(.body.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func dateRow(_ key: String, count: Int, scope: ChequeDateScope) -> some View {
        NavigationLink { ChequeListView(initialFilter: ChequeFilter(dateScope: scope)) } label: {
            HStack(spacing: 12) {
                Text(app.tr(key)).font(.body).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(count.formatted(.number.locale(app.preferences.language.locale)))
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.navy).fixedSize()
                Image(systemName: "chevron.forward")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private func notice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

