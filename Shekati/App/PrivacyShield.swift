import SwiftUI
import UIKit

/// Covers the entire app scene, including editor, photo and settlement sheets.
/// A cover attached only to the root SwiftUI view sits below presented sheets.
@MainActor
final class PrivacyShield {
    private var window: UIWindow?
    private var hiddenAccessibilityWindows: [(window: UIWindow, wasHidden: Bool)] = []

    func update(app: AppState, phase: ScenePhase) {
        guard app.preferences.appLockEnabled, phase != .active || app.lock.isLocked else {
            for captured in hiddenAccessibilityWindows {
                captured.window.accessibilityElementsHidden = captured.wasHidden
            }
            hiddenAccessibilityWindows.removeAll()
            window?.isHidden = true
            window?.rootViewController = nil
            window = nil
            return
        }
        let scene = window?.windowScene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        guard let scene else { return }
        let shield = window ?? UIWindow(windowScene: scene)
        for underlying in scene.windows where underlying !== shield {
            underlying.endEditing(true)
            if !hiddenAccessibilityWindows.contains(where: { $0.window === underlying }) {
                hiddenAccessibilityWindows.append((underlying, underlying.accessibilityElementsHidden))
            }
            underlying.accessibilityElementsHidden = true
        }
        shield.frame = scene.coordinateSpace.bounds
        shield.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        shield.backgroundColor = .systemGroupedBackground
        let cover = PrivacyShieldView(inactive: phase != .active)
            .environment(app)
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, app.preferences.language == .arabic ? .rightToLeft : .leftToRight)
            .preferredColorScheme(app.preferences.appearance == .system ? nil :
                                  app.preferences.appearance == .dark ? .dark : .light)
        let controller = UIHostingController(rootView: cover)
        controller.view.accessibilityViewIsModal = true
        shield.rootViewController = controller
        shield.isUserInteractionEnabled = phase == .active
        shield.isHidden = false
        window = shield
    }
}

@MainActor
private struct PrivacyShieldView: View {
    @Environment(AppState.self) private var app
    let inactive: Bool
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            BrandMark()
            Text(app.tr(inactive ? "Shekati" : "Your cheques, protected")).font(.title2.bold())
            if !inactive {
                Text(app.tr("Unlock to view your records")).foregroundStyle(.secondary)
                Button {
                    Task { await app.lock.unlock() }
                } label: {
                    Label(app.tr("Unlock"), systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(app.lock.isAuthenticating)
                if app.lock.errorMessage != nil {
                    Text(app.tr("Could not unlock. Try again using biometrics or your device passcode."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
    }
}
