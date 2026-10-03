import SwiftUI
import ShekatiCore

@MainActor
struct ChequeRowView: View {
    @Environment(AppState.self) private var app
    let record: ChequeRecord

    private var title: String {
        if !record.party.isEmpty { return record.party }
        if !record.number.isEmpty { return app.tr("Cheque") + " " + record.number }
        return app.tr("Cheque")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: record.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(record.direction == .incoming ? Theme.accent : Theme.navy)
                    .frame(width: 40, height: 40)
                    .background((record.direction == .incoming ? Theme.accent : Theme.navy).opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(app.tr(record.direction == .incoming ? "Incoming" : "Outgoing"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(CurrencyMath.format(minorUnits: record.amountMinorUnits, currencyCode: record.currencyCode,
                                         locale: app.preferences.language.locale))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(record.direction == .incoming ? Theme.accent : Theme.navy)
            }
            HStack(spacing: 8) {
                Label(app.formatDay(record.dueDate), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(record.snapshot.isOverdue(on: .today) ? Theme.red : .secondary)
                    .accessibilityLabel(app.tr("Due date") + ": " + app.formatDay(record.dueDate))
                Spacer(minLength: 4)
                StatusPill(snapshot: record.snapshot)
            }
            if !record.bank.isEmpty || (!record.number.isEmpty && !record.party.isEmpty) {
                HStack(spacing: 8) {
                    if !record.bank.isEmpty { Text(record.bank).lineLimit(1) }
                    if !record.bank.isEmpty && !record.number.isEmpty && !record.party.isEmpty {
                        Text("·").accessibilityHidden(true)
                    }
                    if !record.number.isEmpty && !record.party.isEmpty {
                        Text(app.tr("No.") + " " + record.number).lineLimit(1)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.navy.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
