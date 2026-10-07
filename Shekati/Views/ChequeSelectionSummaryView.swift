import SwiftUI
import ShekatiCore

@MainActor
struct ChequeSelectionSummaryView: View {
    @Environment(AppState.self) private var app
    let summary: ChequeSelectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(app.tr("Selected cheques")).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(DisplayFormatting.count(summary.count, locale: app.preferences.language.locale))
                    .monospacedDigit().fontWeight(.semibold)
                    .accessibilityIdentifier("selectedChequeCount")
            }.font(.subheadline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.tr("Selected total")).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    total.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.tr("Selected total"))
                    total
                }
            }
            .font(.headline)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var total: some View {
        if summary.hasCurrencyConflict {
            Text(app.tr("Select cheques in one currency")).font(.footnote).foregroundStyle(.orange)
        } else if summary.hasOverflow {
            Text(app.tr("Total exceeds supported range")).font(.footnote).foregroundStyle(.orange)
        } else if summary.hasInvalidValues {
            Text(app.tr("Total unavailable")).font(.footnote).foregroundStyle(.orange)
        } else if let value = summary.totalMinorUnits {
            Text(CurrencyMath.format(minorUnits: value, currencyCode: summary.currencyCode ?? app.currencyCode,
                                     locale: app.preferences.language.locale))
                .monospacedDigit().foregroundStyle(Theme.accent)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("selectedChequeAmount")
        } else {
            Text("—").accessibilityIdentifier("selectedChequeAmount")
        }
    }
}
