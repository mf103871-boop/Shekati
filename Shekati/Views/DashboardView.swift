import SwiftUI
import SwiftData
import ShekatiCore

@MainActor
struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    private var snapshots: [ChequeSnapshot] { records.map(\.snapshot) }
    private var metrics: DashboardMetrics { DashboardMetrics(cheques: snapshots, today: app.today) }
    private var upcoming: [ChequeRecord] {
        records.filter { $0.snapshot.isOutstanding }.sorted {
            $0.dueDate == $1.dueDate ? $0.id.uuidString < $1.id.uuidString : $0.dueDate < $1.dueDate
        }.prefix(4).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.tr("Everything in its time.")).font(.title2.weight(.bold))
                        Text(app.tr("A clear view of your next commitments.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.top, 6)
                if app.currencyConflict {
                    NoticeView(title: app.tr("Different currencies found"),
                        message: app.tr("Records from another device use a different currency. Resolve these records before adding new cheques. Totals are hidden to avoid mixing currencies."),
                        symbol: "exclamationmark.triangle.fill", color: .red)
                } else if metrics.hasAmountOverflow {
                    NoticeView(title: app.tr("Total exceeds supported range"),
                        message: app.tr("View individual cheque amounts. Totals cannot be displayed accurately for these records."),
                        symbol: "exclamationmark.triangle.fill")
                } else {
                    outstandingHero
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { totalCard(.incoming); totalCard(.outgoing) }
                        VStack(spacing: 12) { totalCard(.incoming); totalCard(.outgoing) }
                    }
                }
                VStack(spacing: 0) {
                    dateLink("Due today", count: metrics.todayCount, icon: "calendar", scope: .today)
                    Divider().padding(.leading, 52)
                    dateLink("Within 7 days", count: metrics.upcomingCount, icon: "clock", scope: .upcoming)
                    Divider().padding(.leading, 52)
                    dateLink("Overdue", count: metrics.overdueCount, icon: "exclamationmark.circle", scope: .overdue)
                }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                if app.notifications.isDenied {
                    NavigationLink { SettingsView() } label: {
                        NoticeView(title: app.tr("Notifications are off"),
                            message: app.tr("Enable notifications in Settings so your scheduled reminders can appear."),
                            symbol: "bell.slash")
                    }.buttonStyle(.plain)
                }
                if app.notifications.authorizationStatus != .notDetermined,
                   !app.notifications.isDenied, let uncovered = app.notifications.firstUncoveredDate {
                    NoticeView(title: app.tr("Refresh upcoming reminders"),
                        message: app.tr("Open the app before") + " " + app.formatDay(LocalDay(date: uncovered)) +
                        ". " + app.tr("Some later reminders still need scheduling."), symbol: "bell.badge")
                }
                if let message = app.persistenceMessage {
                    NoticeView(title: app.tr("Could not save changes."), message: message,
                               symbol: "externaldrive.badge.exclamationmark", color: .red)
                }
                HStack {
                    Text(app.tr("Next cheques")).font(.title3.bold())
                    Spacer()
                    NavigationLink { ChequeListView() } label: { Text(app.tr("See all")).font(.subheadline) }
                }
                if upcoming.isEmpty {
                    EmptyStateView(title: app.tr("A fresh start"),
                        message: app.tr("Add your first cheque and let Shekati keep the dates in view."),
                        systemImage: "checkmark.rectangle.stack")
                        .frame(minHeight: 190).shekatiCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(upcoming) { record in
                            NavigationLink { ChequeDetailView(record: record) } label: {
                                ChequeRowView(record: record).padding(.vertical, 12).padding(.horizontal, 16)
                            }.buttonStyle(.plain)
                            if record.id != upcoming.last?.id { Divider().padding(.horizontal, 16) }
                        }
                    }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                }
            }.padding(20)
        }.background(Theme.background)
            .navigationTitle(app.tr("Shekati"))
    }

    private var outstandingHero: some View {
        NavigationLink { ChequeListView(initialFilter: ChequeFilter(outstandingOnly: true)) } label: {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.tr("Total outstanding cheques")).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                Text(app.formatAmount(metrics.incomingMinorUnits + metrics.outgoingMinorUnits))
                    .font(.largeTitle.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                Divider().overlay(Color.white.opacity(0.15))
                HStack {
                    Label(app.tr("Outstanding cheques"), systemImage: "checkmark.rectangle.stack")
                    Spacer()
                    Text(snapshots.filter(\.isOutstanding).count.formatted(.number.locale(app.preferences.language.locale)))
                        .monospacedDigit()
                }.font(.caption).foregroundStyle(.white.opacity(0.8))
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brandBackground, in: RoundedRectangle(cornerRadius: 26))
        }.buttonStyle(.plain)
    }

    private func totalCard(_ direction: ChequeDirection) -> some View {
        NavigationLink { ChequeListView(initialFilter: ChequeFilter(direction: direction, outstandingOnly: true)) } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.secondary)
                }
                Text(app.tr(direction == .incoming ? "To collect" : "To pay"))
                    .font(.subheadline).foregroundStyle(.secondary)
                AmountText(minorUnits: direction == .incoming ? metrics.incomingMinorUnits : metrics.outgoingMinorUnits,
                           direction: direction).font(.title2.bold())
                    .minimumScaleFactor(0.65).lineLimit(1)
                Text(app.tr("Outstanding cheques")).font(.caption).foregroundStyle(.secondary)
            }.shekatiCard()
        }.buttonStyle(.plain)
    }

    private func dateLink(_ key: String, count: Int, icon: String, scope: ChequeDateScope) -> some View {
        NavigationLink { ChequeListView(initialFilter: ChequeFilter(dateScope: scope)) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 26)
                    .foregroundStyle(scope == .overdue && count > 0 ? .red : Theme.accent)
                Text(app.tr(key)).font(.subheadline.weight(.medium))
                Spacer()
                Text(count.formatted(.number.locale(app.preferences.language.locale))).font(.title3.bold()).monospacedDigit()
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.secondary)
            }.padding(18).foregroundStyle(.primary)
        }.buttonStyle(.plain)
    }
}
