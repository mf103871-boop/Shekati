import SwiftUI
import ShekatiCore

@MainActor
enum Theme {
    static let accent = Color("AccentColor")
    static let navy = Color("Navy")
    static let brandBackground = Color(red: 19 / 255, green: 42 / 255, blue: 70 / 255)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let red = Color.red
}

@MainActor
private struct ShekatiCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

extension View { @MainActor func shekatiCard() -> some View { modifier(ShekatiCard()) } }

/// Keeps long values visible in narrow windows and at accessibility text sizes.
@MainActor
struct ResponsiveValueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

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
            Text(title).foregroundStyle(.secondary)
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
    @Environment(AppState.self) private var app
    let minorUnits: Int64
    var direction: ChequeDirection? = nil
    var body: some View {
        Text(app.formatAmount(minorUnits))
            .monospacedDigit()
            .foregroundStyle(direction == .incoming ? Theme.accent : .primary)
            .accessibilityLabel(app.formatAmount(minorUnits))
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
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.accent)
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
