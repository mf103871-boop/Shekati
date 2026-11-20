import SwiftUI
import ShekatiCore

@MainActor
struct ChequeRowView: View {
    @Environment(AppState.self) private var app
    @AppStorage("shekati.hideAmounts") private var hidden = false
    let record: ChequeRecord
    var position: ChequePosition? = nil
    var needsReview = false
    private var title: String { record.party.isEmpty ? app.tr("Cheque") : record.party }
    private var direction: String { app.tr(record.direction == .incoming ? "Incoming" : "Outgoing") }
    private var tint: Color { record.direction == .incoming ? Theme.incoming : Theme.outgoing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Label(direction, systemImage: record.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(tint.opacity(0.13), in: Capsule())
            }
            ViewThatFits(in: .horizontal) {
                HStack { amount; Spacer(minLength: 8); number }
                VStack(alignment: .leading, spacing: 3) { amount; number }
            }
            if let position, position.isOpen && position.paid > 0 {
                ResponsiveValueRow(title: app.tr("Remaining"), value: hidden ? "••••" :
                    DisplayFormatting.amount(minorUnits: position.remaining, currencyCode: record.currencyCode,
                                             locale: app.preferences.language.locale))
                    .font(.footnote)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(app.formatDay(record.dueDate)).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if needsReview || position != nil {
                    Text(app.tr(needsReview ? "Needs review" : position?.state.title ?? "Pending")).font(.caption.weight(.semibold)).foregroundStyle(tint)
                } else { StatusPill(snapshot: record.snapshot) }
            }
        }.padding(.vertical, 12).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cheque-row-\(record.id.uuidString)")
    }
    private var amount: some View {
        ReadableCurrencyAmount(minorUnits: record.amountMinorUnits, currencyCode: record.currencyCode,
                               formatted: DisplayFormatting.amount(minorUnits: record.amountMinorUnits,
                                                                   currencyCode: record.currencyCode, locale: app.preferences.language.locale))
            .font(.body.weight(.semibold)).foregroundStyle(.primary)
    }
    private var number: some View {
        Text(verbatim: record.number.isEmpty ? "—" : "#" + record.number)
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .environment(\.layoutDirection, .leftToRight)
    }
}
