import SwiftUI
import SwiftData
import ShekatiCore

/// Planning uses every active cheque, independently of filters on the main list.
@MainActor
struct ChequeFreeDaysView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ChequeRecord> { $0.deletedAt == nil }) private var records: [ChequeRecord]
    @State private var fromDate = LocalDay.today.date()
    @State private var throughDate = LocalDay.today.adding(days: 90).date()
    @State private var plannedDate: PlannedChequeDate?

    private var canAddCheque: Bool { !app.currencyConflict && !app.currencyCode.isEmpty }
    private var layoutDirection: LayoutDirection {
        app.preferences.language == .arabic ? .rightToLeft : .leftToRight
    }

    var body: some View {
        let from = LocalDay(date: fromDate)
        let through = LocalDay(date: throughDate)
        let availability = ChequeAvailability(cheques: records.map(\.snapshot), from: from, through: through)
        let calendar = weekdayCalendar
        NavigationStack {
            List {
                Section {
                    DatePicker(app.tr("From"), selection: $fromDate,
                               in: app.today.date()..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                        .accessibilityIdentifier("freeDaysFromDate")
                    DatePicker(app.tr("Through"), selection: $throughDate,
                               in: app.today.date()..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                        .accessibilityIdentifier("freeDaysThroughDate")
                } footer: {
                    Text(app.tr("Days with no unpaid outgoing cheques due, across all banks. Choose a period of up to 366 days."))
                }

                if !availability.isValidRange || from < app.today {
                    Section {
                        Label(app.tr("Choose a date range from today, with the end on or after the start, up to 366 days."),
                              systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline).foregroundStyle(.orange)
                            .accessibilityIdentifier("freeDaysRangeError")
                    }
                } else {
                    if !canAddCheque {
                        Section {
                            Label(app.tr("Resolve the currency setting before adding a cheque."),
                                  systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                    }
                    Section {
                        if availability.freeDays.isEmpty {
                            Text(app.tr("No free days in this period. Try another date range."))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("noFreeChequeDays")
                        } else {
                            ForEach(availability.freeDays, id: \.iso) { day in
                                Button {
                                    // Recheck the live view's scope before opening a draft.
                                    guard canAddCheque, day >= app.today,
                                          availability.freeDays.contains(day) else { return }
                                    plannedDate = PlannedChequeDate(day: day)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(weekday(day, calendar: calendar))
                                                .font(.body.weight(.medium)).foregroundStyle(.primary)
                                            Text(app.formatDay(day))
                                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                                .environment(\.layoutDirection, .leftToRight)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "plus.circle")
                                            .font(.title3).foregroundStyle(Theme.accent)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!canAddCheque)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(weekday(day, calendar: calendar) + " · " + app.formatDay(day))
                                .accessibilityHint(app.tr("Add an outgoing cheque on this day"))
                                .accessibilityIdentifier("freeDay-" + day.iso)
                            }
                        }
                    } header: {
                        HStack {
                            Text(app.tr("Free days"))
                            Spacer()
                            Text(DisplayFormatting.count(availability.freeDays.count, locale: app.preferences.language.locale))
                                .monospacedDigit()
                                .accessibilityIdentifier("freeDaysCount")
                        }
                    } footer: {
                        Text(app.tr("Tap a day to add an outgoing cheque with this due date."))
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(app.tr("Free days"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(app.tr("Done")) { dismiss() }
                        .accessibilityIdentifier("closeFreeDays")
                }
            }
            .sheet(item: $plannedDate) { plan in
                NavigationStack {
                    ChequeEditorView(initialDirection: .outgoing, initialDueDate: plan.day)
                }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, layoutDirection)
            }
        }
        .environment(\.locale, app.preferences.language.locale)
        .environment(\.layoutDirection, layoutDirection)
        .onChange(of: app.today) { _, today in
            if LocalDay(date: fromDate) < today { fromDate = today.date() }
            if LocalDay(date: throughDate) < today { throughDate = today.date() }
        }
    }

    private var weekdayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = app.preferences.language.locale
        return calendar
    }

    private func weekday(_ day: LocalDay, calendar: Calendar) -> String {
        let index = calendar.component(.weekday, from: day.date(calendar: calendar)) - 1
        return calendar.weekdaySymbols[index]
    }
}

private struct PlannedChequeDate: Identifiable {
    let day: LocalDay
    var id: String { day.iso }
}
