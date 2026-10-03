import SwiftUI
import ShekatiCore

/// Name/number and amount/date use aligned groups that stay readable on an iPhone.
@MainActor
struct ChequeTableHeaderView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var nameMinimum: CGFloat = 112
    @ScaledMetric(relativeTo: .subheadline) private var amountMinimum: CGFloat = 146

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(app.tr("Name and number") + " · " + app.tr("Amount and due date"))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.tr("Name"))
                            Text(app.tr("Cheque number")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minWidth: nameMinimum, maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(app.tr("Amount"))
                            Text(app.tr("Due date")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minWidth: amountMinimum, alignment: .trailing)
                    }
                    Text(app.tr("Name and number") + " · " + app.tr("Amount and due date"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
struct ChequeRowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var nameMinimum: CGFloat = 112
    @ScaledMetric(relativeTo: .subheadline) private var amountMinimum: CGFloat = 146
    let record: ChequeRecord

    private var title: String { record.party.isEmpty ? app.tr("Cheque") : record.party }
    private var amount: String {
        CurrencyMath.format(minorUnits: record.amountMinorUnits, currencyCode: record.currencyCode,
                            locale: app.preferences.language.locale)
    }
    private var directionLabel: String { app.tr(record.direction == .incoming ? "Incoming" : "Outgoing") }
    private var overdue: Bool { record.snapshot.isOverdue(on: app.today) }
    private var statusLabel: String {
        if overdue {
            return record.status == .returned ? app.tr("Returned") + " · " + app.tr("Overdue") : app.tr("Overdue")
        }
        switch record.status {
        case .pending: return app.tr("Pending")
        case .settled: return app.tr(record.direction == .incoming ? "Collected" : "Paid")
        case .returned: return app.tr("Returned")
        case .cancelled: return app.tr("Cancelled")
        }
    }
    private var statusColor: Color {
        if overdue || record.status == .returned { return Theme.red }
        return record.status == .settled ? .green : .secondary
    }
    private var statusSymbol: String {
        if overdue { return "exclamationmark.circle" }
        switch record.status {
        case .pending: return "clock"
        case .settled: return "checkmark.circle"
        case .returned: return "arrow.uturn.backward.circle"
        case .cancelled: return "xmark.circle"
        }
    }
    private var shortDueDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = app.preferences.language.locale
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: record.dueDate.date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                stackedFields
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        identityFields
                            .frame(minWidth: nameMinimum, maxWidth: .infinity, alignment: .leading)
                        financialFields
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: amountMinimum, alignment: .trailing)
                    }
                    stackedFields
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusText
                    Spacer(minLength: 8)
                    Text(directionLabel).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    statusText
                    Text(directionLabel).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ", " + app.tr("No.") + " " +
                            (record.number.isEmpty ? app.tr("Not provided") : record.number) + ", " +
                            amount + ", " + app.tr("Due date") + " " + app.formatDay(record.dueDate) + ", " +
                            statusLabel + ", " + directionLabel)
        .accessibilityIdentifier("cheque-row-\(record.id.uuidString)")
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            numberText.font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var numberText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(app.tr("No."))
            Text(record.number.isEmpty ? "—" : record.number)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .lineLimit(2)
        }
    }
    private var financialFields: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(record.status == .settled ? Color.green : Color.primary)
                .environment(\.layoutDirection, .leftToRight)
            Text(shortDueDate)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(overdue ? Theme.red : .secondary)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
    private var stackedFields: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            numberText.font(.subheadline).foregroundStyle(.secondary)
            Text(app.tr("Amount")).font(.footnote).foregroundStyle(.secondary)
            Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true)
            Text(app.tr("Due date")).font(.footnote).foregroundStyle(.secondary)
            Text(shortDueDate).font(.subheadline).monospacedDigit()
                .foregroundStyle(overdue ? Theme.red : .secondary)
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var statusText: some View {
        Label(statusLabel, systemImage: statusSymbol)
            .foregroundStyle(statusColor)
    }
}
