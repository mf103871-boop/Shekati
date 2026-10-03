import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable
final class AppLockController {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    var languageCode = "ar"

    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var attempt = UUID()

    func synchronize(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if newValue { lock() }
        else {
            attempt = UUID()
            context?.invalidate()
            context = nil
            isAuthenticating = false
            isLocked = false
            errorMessage = nil
        }
    }

    func lock() {
        guard enabled else { return }
        attempt = UUID()
        context?.invalidate()
        context = nil
        isAuthenticating = false
        errorMessage = nil
        isLocked = true
    }

    func unlock() async {
        guard enabled, isLocked, !isAuthenticating else { return }
        let current = LAContext()
        current.localizedCancelTitle = languageCode.hasPrefix("ar") ? "إلغاء" : "Cancel"
        var error: NSError?
        guard current.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = localized("فعّل رمز دخول للآيفون حتى تتمكن من فتح شيكاتي.", "Set an iPhone passcode to unlock Shekati.")
            return
        }
        let currentAttempt = UUID()
        attempt = currentAttempt
        context = current
        isAuthenticating = true
        errorMessage = nil
        do {
            let success = try await current.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: localized("افتح شيكاتي للوصول إلى بيانات الشيكات.", "Unlock Shekati to access your cheque details."))
            guard attempt == currentAttempt, enabled else { return }
            isLocked = !success
            isAuthenticating = false
            context = nil
        } catch {
            guard attempt == currentAttempt, enabled else { return }
            isAuthenticating = false
            context = nil
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .systemCancel && code != .appCancel {
                errorMessage = localized("تعذر التحقق من هويتك. حاول مجددًا باستخدام بصمتك أو رمز دخول الآيفون.", "Authentication failed. Try again using biometrics or your iPhone passcode.")
            }
        }
    }

    private func localized(_ arabic: String, _ english: String) -> String { languageCode.hasPrefix("ar") ? arabic : english }
}
