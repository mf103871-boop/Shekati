import SwiftUI
import ShekatiCore

@MainActor
enum Theme {
    static let accent = Color("AccentColor")
    /// Text and symbols on the filled accent button use a dark ink on its light mint variant.
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.04, green: 0.15, blue: 0.16, alpha: 1) : .white
    })
    static let navy = Color("Navy")
    static let brandBackground = Color(red: 18 / 255, green: 78 / 255, blue: 82 / 255)
    static let incoming = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.53, green: 0.85, blue: 0.69, alpha: 1) : UIColor(red: 0.14, green: 0.44, blue: 0.30, alpha: 1) })
    static let outgoing = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.60, green: 0.76, blue: 0.97, alpha: 1) : UIColor(red: 0.19, green: 0.36, blue: 0.58, alpha: 1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let red = Color.red
}

@MainActor
private struct ShekatiCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View { @MainActor func shekatiCard() -> some View { modifier(ShekatiCard()) } }

/// Keeps long values visible in narrow windows and at accessibility text sizes.
@MainActor
struct ResponsiveValueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    var stackedTitleStyle = AnyShapeStyle(.secondary)

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { stacked }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(title).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        Text(value).fixedSize(horizontal: true, vertical: false)
                    }
                    stacked
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(stackedTitleStyle)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: { Text(message) }
    }
}

@MainActor
struct AmountText: View {
    @AppStorage("shekati.hideAmounts") private var hidden = false
    @Environment(AppState.self) private var app
    let minorUnits: Int64
    var direction: ChequeDirection? = nil
    var body: some View {
        Text(hidden ? "••••" : app.formatAmount(minorUnits))
            .monospacedDigit()
            .foregroundStyle(direction == .incoming ? Theme.accent : .primary)
            .accessibilityLabel(hidden ? app.tr("Amounts hidden") : app.formatAmount(minorUnits))
    }
}

/// A monetary value must never wrap between its integer and fractional digits.
/// Keep the preferred font; long values use a separate currency label and can pan.
@MainActor
struct ReadableCurrencyAmount: View {
    @AppStorage("shekati.hideAmounts") private var hidden = false
    @Environment(AppState.self) private var app
    let minorUnits: Int64
    let currencyCode: String
    let formatted: String

    var body: some View {
        if hidden { Text("••••").accessibilityLabel(app.tr("Amounts hidden")) } else {
        ViewThatFits(in: .horizontal) {
            Text(formatted).fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal) {
                    Text(CurrencyMath.editable(minorUnits: minorUnits, currencyCode: currencyCode))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                Text(currencyCode).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .monospacedDigit()
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(formatted)
        }
    }
}

@MainActor
struct StatusPill: View {
    @Environment(AppState.self) private var app
    let snapshot: ChequeSnapshot
    private var label: String {
        if snapshot.isOverdue(on: app.today) {
            return snapshot.status == .returned ? app.tr("Returned") + " · " + app.tr("Overdue") : app.tr("Overdue")
        }
        switch snapshot.status {
        case .pending: return app.tr("Pending")
        case .settled: return app.tr(snapshot.direction == .incoming ? "Collected" : "Paid")
        case .returned: return app.tr("Returned")
        case .cancelled: return app.tr("Cancelled")
        }
    }
    private var color: Color {
        if snapshot.isOverdue(on: app.today) { return .red }
        switch snapshot.status {
        case .settled: return Theme.accent
        case .returned: return .orange
        case .cancelled: return .secondary
        case .pending: return .blue
        }
    }
    var body: some View {
        Text(label).font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

@MainActor
struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Theme.brandBackground)
            Image(systemName: "checkmark.rectangle.stack.fill")
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
        }.frame(width: 60, height: 60).accessibilityHidden(true)
    }
}

@MainActor
struct NoticeView: View {
    let title: String
    let message: String
    let symbol: String
    var color: Color = .orange
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).shekatiCard()
    }
}
