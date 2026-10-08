import SwiftUI
import ShekatiCore

@MainActor
struct ChequeSelectionSummaryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: ChequeSelectionSummary
    var compact = false

    var body: some View {
        Group {
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        countLine.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        totalLine.fixedSize(horizontal: true, vertical: false)
                    }
                    summaryLines
                }
            } else { summaryLines }
        }
        .padding(.horizontal, 16).padding(.vertical, compact ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var summaryLines: some View {
        VStack(alignment: .leading, spacing: 8) {
            countLine
            totalLine
        }
    }

    private var countLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(app.tr("Selected cheques")).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(DisplayFormatting.count(summary.count, locale: app.preferences.language.locale))
                .monospacedDigit().fontWeight(.semibold).fixedSize()
                .accessibilityIdentifier("selectedChequeCount")
        }.font(.subheadline)
    }

    @ViewBuilder private var totalLine: some View {
        if dynamicTypeSize.isAccessibilitySize { stackedTotal }
        else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.tr("Selected total")).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    total.fixedSize(horizontal: true, vertical: false)
                }
                stackedTotal
            }.font(.headline)
        }
    }

    private var stackedTotal: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.tr("Selected total"))
            total.fixedSize(horizontal: false, vertical: true)
        }.font(.headline)
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
