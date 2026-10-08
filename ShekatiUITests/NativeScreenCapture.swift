import XCTest
import UIKit

extension XCTestCase {
    /// Capture the physical screen, not the app's portrait-oriented backing window. On iOS 26
    /// app.screenshot() can crop landscape content to the former portrait width and pad it black.
    func attachNativeScreenshot(in app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Keep Apple's native image untouched. Validate its two pixel dimensions against the
        // current window, allowing screenshot orientation metadata to describe the pixel order.
        guard let pixels = screenshot.image.cgImage, app.windows.firstMatch.exists else { return }
        let frame = app.windows.firstMatch.frame
        guard frame.width > 0 && frame.height > 0 else { return }
        let shortScale = CGFloat(min(pixels.width, pixels.height)) / min(frame.width, frame.height)
        let longScale = CGFloat(max(pixels.width, pixels.height)) / max(frame.width, frame.height)
        XCTAssertGreaterThan(shortScale, 0)
        XCTAssertEqual(shortScale, longScale, accuracy: 0.01,
                       "A native screen capture must preserve the device viewport's aspect ratio")
    }

    /// A 180-degree landscape flip has the same bounds before and after. Pass through portrait
    /// so an old landscape frame cannot satisfy the wait while the interface is still rotating.
    func rotateIPhone(to orientation: UIDeviceOrientation, in app: XCUIApplication) {
        let current = XCUIDevice.shared.orientation
        if current.isLandscape && orientation.isLandscape && current != orientation {
            setOrientationAndWait(.portrait, in: app)
        }
        setOrientationAndWait(orientation, in: app)
    }

    private func setOrientationAndWait(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        var lastFrame = CGRect.null
        var stableSince: Date?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            let correctAspect = frame.width > 0 && (orientation.isLandscape ?
                frame.width > frame.height : frame.height > frame.width)
            guard correctAspect else { stableSince = nil; return false }
            if frame != lastFrame || stableSince == nil {
                lastFrame = frame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince!) >= 0.75
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed,
                       "The native iPhone window must finish rotating and settle before interaction or capture")
    }
}
