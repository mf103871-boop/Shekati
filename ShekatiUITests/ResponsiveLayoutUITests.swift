import XCTest
import UIKit

/// Runs on the CI's compact, standard and large iPhone destinations. Fixtures are entered through
/// the real editor into --ui-testing's in-memory store; production data and iCloud are never used.
final class ResponsiveLayoutUITests: XCTestCase {
    private let chequeNumber = "000010"
    private let amount = "1234567890.12"
    private let payee = "Pixel Fixture"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testEnglishPortraitAndLandscape() { exerciseLayout(arabic: false, largeText: false) }
    func testArabicPortraitAndLandscape() { exerciseLayout(arabic: true, largeText: false) }
    func testEnglishAccessibilityPortraitAndLandscape() { exerciseLayout(arabic: false, largeText: true) }
    func testArabicAccessibilityPortraitAndLandscape() { exerciseLayout(arabic: true, largeText: true) }

    private func exerciseLayout(arabic: Bool, largeText: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (arabic ? ["--arabic"] : [])
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["chooseCurrency"].waitForExistence(timeout: 15))
        reveal(app.buttons["chooseCurrency"], in: app)
        assertVisibleBounds(app.buttons["chooseCurrency"], in: app)
        app.buttons["chooseCurrency"].tap()
        let currency = app.buttons["currency_USD"]
        XCTAssertTrue(currency.waitForExistence(timeout: 5))
        // USD is the first visible row and touches the sheet's large navigation title.
        // Check its actual bounds and tap target without requiring artificial space above it.
        assertVisibleBounds(currency, in: app)
        let navigationBottom = app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        XCTAssertGreaterThanOrEqual(currency.frame.minY, navigationBottom - 1)
        currency.tap()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 8))
        rotate(.portrait, in: app)
        XCTAssertTrue(app.buttons["addCheque"].isHittable)
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        selectOutgoing(in: app, arabic: arabic)
        let amountField = app.textFields["amountField"]
        reveal(amountField, in: app)
        amountField.tap()
        type(amount, into: "amountField", expected: amount, in: app)
        for (identifier, text) in [("partyField", payee), ("chequeNumberField", chequeNumber)] {
            let next = app.buttons[arabic ? "التالي" : "Next"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isHittable)
            next.tap()
            // The real Next control must focus the target. Retapping would mask a broken handoff.
            type(text, into: identifier, expected: text, in: app)
        }
        dismissKeyboard(in: app, arabic: arabic)
        assertVisibleBounds(app.buttons["saveCheque"], in: app)
        app.buttons["saveCheque"].tap()
        waitForAbsence(app.buttons["saveCheque"])
        let negative = app.descendants(matching: .any).matching(NSPredicate(
            format: "(label CONTAINS %@ OR label CONTAINS %@) AND label CONTAINS %@ AND label CONTAINS %@",
            "-", "−", "234", "890")).firstMatch
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation, in: app)
            reveal(negative, in: app)
            let label = negative.label
            XCTAssertEqual(label.filter { "0123456789".contains($0) }, "123456789012")
            XCTAssertTrue(label.contains("-") || label.contains("−"))
            assertVisibleBounds(negative, in: app)
            capture(app, orientation.isLandscape ? "02 signed balance landscape" : "01 signed balance portrait")
        }
    }

    private func selectOutgoing(in app: XCUIApplication, arabic: Bool) {
        let title = arabic ? "صادر" : "Outgoing"
        let segmented = app.segmentedControls["chequeDirectionPicker"]
        if segmented.exists {
            let option = segmented.buttons[title]
            reveal(option, in: app)
            option.tap()
            XCTAssertTrue(option.isSelected, "The outgoing direction must be selected")
        } else {
            // Accessibility text uses a menu so both direction labels remain readable.
            let picker = element("chequeDirectionPicker", in: app)
            reveal(picker, in: app)
            picker.tap()
            let option = app.buttons[title].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5) && option.isHittable)
            option.tap()
            // UIKit temporarily replaces the picker accessibility element while dismissing
            // its menu. Match the chosen value in one snapshot rather than reading exists,
            // label and value from three potentially different animation frames.
            let selectedPicker = app.buttons.matching(identifier: "chequeDirectionPicker")
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title)).firstMatch
            let selected = selectedPicker.waitForExistence(timeout: 10)
            if !selected { diagnostics(app, "Direction menu did not expose the chosen outgoing value") }
            XCTAssertTrue(selected, "The menu must expose the chosen outgoing direction as its current value")
        }
    }

    private func rotate(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        rotateIPhone(to: orientation, in: app)
    }

    private func type(_ text: String, into identifier: String, expected: String, in app: XCUIApplication) {
        let field = app.textFields[identifier]
        var previousFrame = CGRect.null
        var previousKeyboardFrame = CGRect.null
        var stableSince: Date?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let root = try? app.snapshot() else {
                stableSince = nil
                return false
            }
            // Read one instant of the interface. Fetching each frame independently mixes
            // generations of the keyboard hierarchy and can exhaust a poll before it ends.
            var elements: [any XCUIElementSnapshot] = [root]
            var index = 0
            while index < elements.count {
                let children = elements[index].children
                elements.append(contentsOf: children)
                index += 1
            }
            guard let window = elements.first(where: { $0.elementType == .window && !$0.frame.isEmpty })?.frame,
                  let target = elements.first(where: { $0.elementType == .textField && $0.identifier == identifier }),
                  target.isEnabled,
                  let keyboardFrame = elements.first(where: { $0.elementType == .keyboard && $0.frame.intersects(window) })?.frame else {
                stableSince = nil
                return false
            }
            let frame = target.frame
            let visible = elements.filter { $0.frame.height > 0 && $0.frame.intersects(window) }
            let navigationBottom = visible.filter { $0.elementType == .navigationBar }
                .map { $0.frame.maxY }.max() ?? window.minY
            let predictions = visible.first { $0.elementType == .other && $0.label == "Typing Predictions" }
            let accessoryTop = predictions.map { min(keyboardFrame.minY, $0.frame.minY) } ?? keyboardFrame.minY - 48
            let toolbarTop = visible.filter { $0.elementType == .toolbar && $0.frame.minY > navigationBottom }
                .map { $0.frame.minY }.min() ?? keyboardFrame.minY
            let visibleBottom = min(accessoryTop, toolbarTop)
            guard frame.width > 0 && frame.height > 0 && keyboardFrame.height > 0 &&
                frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1 &&
                frame.minY >= navigationBottom && frame.maxY <= visibleBottom else {
                stableSince = nil
                return false
            }
            if frame != previousFrame || keyboardFrame != previousKeyboardFrame || stableSince == nil {
                previousFrame = frame
                previousKeyboardFrame = keyboardFrame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince!) >= 0.5
        }, object: nil)
        // Next must focus and scroll its target above the keyboard before typing begins.
        // Do not retap or drag a focused field: either can move the insertion point.
        let readiness = XCTWaiter.wait(for: [ready], timeout: 15)
        if readiness != .completed { inputDiagnostics(field, in: app, stage: "Target did not settle above keyboard") }
        XCTAssertEqual(readiness, .completed, "The focused field must become fully visible and stable before typing")
        XCTAssertTrue(field.isHittable, "The fully visible target must accept interaction after the keyboard settles")
        if identifier == "partyField" || identifier == "chequeNumberField" {
            typeLongFixture(text, into: field, in: app)
            return
        }
        field.typeText(text)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
        let received = XCTWaiter.wait(for: [accepted], timeout: 5)
        if received != .completed { inputDiagnostics(field, in: app, stage: "Exact input was not received") }
        XCTAssertEqual(received, .completed, "The intended field must receive exactly the supplied fixture text")
    }

    private func typeLongFixture(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        // The hosted Arabic Dynamic Type run acknowledged synthesis before UIKit delivered
        // the fixture. A 31-second pause occurred between two consecutive keyboard events.
        let placeholder = field.placeholderValue
        let identifier = field.identifier
        let clock = ProcessInfo.processInfo
        let deadline = clock.systemUptime + 90
        var acknowledged = ""
        var pending = text[...]
        while !pending.isEmpty {
            guard app.keyboards.firstMatch.exists else {
                inputDiagnostics(field, in: app, stage: "Keyboard disappeared while entering \(identifier)")
                XCTFail("Keyboard disappeared after '\(acknowledged)' in \(identifier).")
                return
            }
            let part = String(pending.prefix(8))
            let expected = acknowledged + part
            field.typeText(part)
            var observed = acknowledged
            var mismatch = false
            let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let raw = field.value as? String ?? ""
                let current = raw == placeholder ? "" : raw
                mismatch = !expected.hasPrefix(current) || !current.hasPrefix(observed)
                observed = current
                return mismatch || current == expected
            }, object: nil)
            let timeout = min(40, max(0, deadline - clock.systemUptime))
            let result = XCTWaiter.wait(for: [delivered], timeout: timeout)
            guard result == .completed && !mismatch && observed == expected else {
                inputDiagnostics(field, in: app, stage: "Input did not arrive intact in \(identifier)")
                XCTFail("Expected prefix '\(expected)' in \(identifier), read '\(observed)'. Input stalled, changed, or lost a character.")
                return
            }
            acknowledged = expected
            pending = pending.dropFirst(part.count)
        }
        XCTAssertEqual(acknowledged, text)
    }

    private func inputDiagnostics(_ field: XCUIElement, in app: XCUIApplication, stage: String) {
        let exists = field.exists
        let identifier = exists ? field.identifier : "<not in the current accessibility tree>"
        let value = exists ? String(describing: field.value) : "<missing>"
        let fixtureState = XCTAttachment(string: "Field: \(identifier)\nExists: \(exists)\nValue: \(value)")
        fixtureState.name = stage + " — isolated fixture field value"
        fixtureState.lifetime = .keepAlways
        add(fixtureState)
        diagnostics(app, stage)
    }

    private func dismissKeyboard(in app: XCUIApplication, arabic: Bool) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons.matching(NSPredicate(format: "label == %@", arabic ? "تم" : "Done"))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(done, "A visible Done control must dismiss the numeric or text keyboard")
        done?.tap()
        waitForAbsence(app.keyboards.firstMatch, timeout: 30)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func chequeRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", chequeNumber)).firstMatch
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed)
    }

    private func assertVisibleBounds(_ element: XCUIElement, in app: XCUIApplication, requireFullHeight: Bool = true) {
        XCTAssertTrue(element.exists && element.isHittable, "The control must be reachable without hidden chrome")
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 1, "The control must not escape the left edge")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "The control must not escape the right edge")
        if requireFullHeight {
            XCTAssertGreaterThanOrEqual(frame.minY, window.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, window.maxY + 1)
        }
    }

    private enum VerticalSearchDirection { case earlier, later }

    /// Use measured navigation/keyboard/toolbars rather than portrait-only fixed top/bottom offsets.
    /// Content can be intentionally wider for the horizontally scrolling spreadsheet, but controls
    /// and accessibility cards still have to fit the viewport.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication,
                        allowHorizontalScroll: Bool = false, searchToward: VerticalSearchDirection = .later,
                        file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        var searchEarlier = searchToward == .earlier
        var targetDescription: String?
        for _ in 0..<16 {
            let frame = window.frame
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.map(\.frame)
                .filter { $0.height > 0 && $0.intersects(frame) }.map(\.maxY).max() ?? frame.minY
            let top = max(frame.minY + 4, navigationBottom + 4)
            let bars = app.toolbars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
            let bottomBar = bars.map(\.frame).filter { $0.height > 0 && $0.intersects(frame) && $0.minY > top }
                .map(\.minY).min() ?? frame.maxY
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists && keyboard.frame.height > 0 ? keyboard.frame.minY - 48 : frame.maxY
            let bottom = min(frame.maxY - 4, min(bottomBar, keyboardTop)) - 4
            let exists = target.exists
            let targetFrame = exists ? target.frame : CGRect.null
            let hasFrame = !targetFrame.isNull && !targetFrame.isEmpty
            if exists && targetDescription == nil {
                let identifier = target.identifier
                targetDescription = identifier.isEmpty ? target.label : identifier
            }
            if hasFrame {
                let fitsHeight = targetFrame.height <= bottom - top
                let verticallyVisible = fitsHeight ? targetFrame.minY >= top && targetFrame.maxY <= bottom :
                    targetFrame.midY >= top && targetFrame.midY <= bottom
                let horizontallyVisible = allowHorizontalScroll ||
                    (targetFrame.minX >= frame.minX - 1 && targetFrame.maxX <= frame.maxX + 1)
                // XCUITest can throw while resolving an offscreen button's activation point.
                // Check measured visibility first, scroll it into view, then require hittability.
                if verticallyVisible && horizontallyVisible && target.isHittable { return }
                searchEarlier = (fitsHeight ? targetFrame.minY : targetFrame.midY) < top
            }
            guard bottom > top + 24 else { break }
            // SwiftUI recycles offscreen Form/List/LazyVStack rows. An absent target has
            // no usable frame; retain the direction from its last frame or the call site.
            let above = searchEarlier
            let targetEdge = targetFrame.height > bottom - top ? targetFrame.midY : (above ? targetFrame.minY : targetFrame.maxY)
            let gap = hasFrame ? (above ? top - targetEdge : targetEdge - bottom) : bottom - top
            let distance = min((bottom - top) * 0.65, max(24, gap * 0.75 + 8))
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let startY = above ? top + 4 : bottom - 4
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY + (above ? distance : -distance) - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        // Reading identifier on a recycled element throws before screenshot/tree capture.
        let description = targetDescription ?? "requested control (not in the current accessibility tree)"
        diagnostics(app, "Unreachable control " + description)
        XCTFail("Expected \(description) to be reachable inside the rotated viewport", file: file, line: line)
    }

    private func capture(_ app: XCUIApplication, _ label: String) {
        let window = app.windows.firstMatch.frame
        attachNativeScreenshot(in: app,
            name: "\(name) — \(Int(window.width))x\(Int(window.height))pt — \(label)")
    }

    private func diagnostics(_ app: XCUIApplication, _ label: String) {
        capture(app, label)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = label + " accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
