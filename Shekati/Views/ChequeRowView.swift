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
    @AppStorage("shekati.hideAmounts") private var hidden = false
    let record: ChequeRecord
    var stateLabel: String? = nil
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
            HStack(alignment: .firstTextBaseline) {
                Text(app.formatDay(record.dueDate)).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if let stateLabel {
                    Text(app.tr(stateLabel)).font(.caption.weight(.semibold)).foregroundStyle(tint)
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
