import XCTest
import UIKit

/// Runs on the CI's compact, standard and large iPhone destinations. Fixtures are entered through
/// the real editor into --ui-testing's in-memory store; production data and iCloud are never used.
final class ResponsiveLayoutUITests: XCTestCase {
    private let chequeNumber = "00001000000000123456"
    private let amount = "1234567890.12"
    private let payee = "International Supplies and Contracting Company - Central Branch 000010"

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
        capture(app, "01 onboarding portrait")
        rotate(.landscapeLeft, in: app)
        reveal(app.buttons["chooseCurrency"], in: app)
        assertVisibleBounds(app.buttons["chooseCurrency"], in: app)
        capture(app, "02 onboarding landscape")
        app.buttons["chooseCurrency"].tap()
        let currency = app.buttons["currency_USD"]
        XCTAssertTrue(currency.waitForExistence(timeout: 5))
        reveal(currency, in: app)
        currency.tap()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 8))
        rotate(.portrait, in: app)
        reveal(app.buttons["addCheque"], in: app)
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        selectOutgoing(in: app, arabic: arabic)
        let amountField = app.textFields["amountField"]
        reveal(amountField, in: app)
        amountField.tap()
        type(amount, into: amountField, expected: amount, in: app)
        for (identifier, text) in [("partyField", payee), ("chequeNumberField", chequeNumber)] {
            let next = app.buttons[arabic ? "التالي" : "Next"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isHittable)
            next.tap()
            // The real Next control must focus the target. Retapping would mask a broken handoff.
            type(text, into: app.textFields[identifier], expected: text, in: app)
        }
        dismissKeyboard(in: app, arabic: arabic)
        reveal(amountField, in: app)
        assertVisibleBounds(amountField, in: app)
        assertVisibleBounds(app.buttons["saveCheque"], in: app)
        capture(app, "03 long cheque entry portrait")

        // Rotation while editing must preserve every draft value and leave input usable.
        rotate(.landscapeLeft, in: app)
        reveal(amountField, in: app)
        assertVisibleBounds(amountField, in: app)
        XCTAssertEqual(amountField.value as? String, amount)
        amountField.tap()
        let landscapeKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.keyboards.firstMatch.exists && amountField.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeKeyboard], timeout: 8), .completed,
                       "The rotated amount field must still accept keyboard focus")
        // A tap can legitimately reposition the caret. Verify focus and the complete draft
        // without making an assumption about UIKit's insertion position inside an existing value.
        XCTAssertEqual(amountField.value as? String, amount)
        capture(app, "04 numeric keyboard landscape")
        dismissKeyboard(in: app, arabic: arabic)
        for (identifier, value) in [("partyField", payee), ("chequeNumberField", chequeNumber)] {
            let field = app.textFields[identifier]
            reveal(field, in: app)
            assertVisibleBounds(field, in: app)
            XCTAssertEqual(field.value as? String, value, "Rotation must preserve the complete draft")
        }
        assertVisibleBounds(app.buttons["saveCheque"], in: app)
        capture(app, "05 long cheque entry landscape")
        app.buttons["saveCheque"].tap()
        waitForAbsence(app.buttons["saveCheque"])
        rotate(.portrait, in: app)
        // The total row combines its VoiceOver children, so assert the public row's complete
        // value rather than relying on an identifier hidden inside that combined element.
        let dashboardTotal = element("dashboardTotal-outgoing", in: app)
        reveal(dashboardTotal, in: app)
        assertVisibleBounds(dashboardTotal, in: app)
        XCTAssertEqual(dashboardTotal.label.filter { "0123456789".contains($0) }, "123456789012",
                       "The dashboard must expose the complete precise amount with English digits")
        capture(app, "06 large amount dashboard portrait")

        let chequesTab = app.tabBars.buttons[arabic ? "الشيكات" : "Cheques"]
        assertVisibleBounds(chequesTab, in: app)
        chequesTab.tap()
        if !largeText {
            // The title belongs to the viewport while the wide columns scroll underneath it.
            let title = app.staticTexts["outgoingTableTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            assertVisibleBounds(title, in: app)
            // Both reading directions must initially expose the value column without a pan.
            let valueHeading = app.staticTexts[arabic ? "القيمة" : "Value"]
            XCTAssertTrue(valueHeading.waitForExistence(timeout: 5))
            assertVisibleBounds(valueHeading, in: app)
        }
        let row = chequeRow(in: app)
        reveal(row, in: app, allowHorizontalScroll: !largeText)
        XCTAssertTrue(row.label.contains(chequeNumber))
        XCTAssertTrue(row.label.contains(amount))
        XCTAssertTrue(row.label.contains(payee))
        if largeText { assertVisibleBounds(row, in: app, requireFullHeight: false) }
        capture(app, "07 long cheque ledger portrait")
        let select = app.buttons["selectChequesButton"]
        reveal(select, in: app)
        select.tap()
        let selectAll = app.buttons["selectAllChequesButton"]
        reveal(selectAll, in: app)
        selectAll.tap()
        assertSelection(in: app)
        capture(app, "08 selected large amount portrait")
        rotate(.landscapeLeft, in: app)
        assertSelection(in: app)
        capture(app, "09 selected large amount landscape left")
        rotate(.landscapeRight, in: app)
        assertSelection(in: app)
        capture(app, "10 selected large amount landscape right")
        reveal(select, in: app)
        select.tap()
        let freeDays = app.buttons["freeChequeDaysButton"]
        reveal(freeDays, in: app)
        assertVisibleBounds(freeDays, in: app)
        freeDays.tap()
        XCTAssertTrue(app.buttons["closeFreeDays"].waitForExistence(timeout: 5))
        for identifier in ["freeDaysFromDate", "freeDaysThroughDate"] {
            let dateControl = element(identifier, in: app)
            reveal(dateControl, in: app)
            assertVisibleBounds(dateControl, in: app)
        }
        capture(app, "11 free due date controls landscape")
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let freeDay = app.buttons["freeDay-" + formatter.string(from: tomorrow)]
        reveal(freeDay, in: app)
        assertVisibleBounds(freeDay, in: app)
        capture(app, "12 free due dates landscape")
        rotate(.portrait, in: app)
        reveal(freeDay, in: app)
        capture(app, "13 free due dates portrait")
        freeDay.tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        let plannedDate = app.staticTexts["plannedDueDateSummary"]
        reveal(plannedDate, in: app)
        assertVisibleBounds(plannedDate, in: app)
        formatter.dateFormat = "dd/MM/yyyy"
        XCTAssertTrue(plannedDate.label.contains(formatter.string(from: tomorrow)))
        capture(app, "14 date-prefilled editor portrait")
        app.buttons[arabic ? "إلغاء" : "Cancel"].tap()
        waitForAbsence(app.buttons["saveCheque"])
        app.buttons["closeFreeDays"].tap()
        waitForAbsence(app.buttons["closeFreeDays"])
        app.tabBars.buttons[arabic ? "الإعدادات" : "Settings"].tap()
        let dataTools = element("dataTools", in: app)
        reveal(dataTools, in: app)
        assertVisibleBounds(dataTools, in: app)
        capture(app, "15 settings portrait")
        rotate(.landscapeLeft, in: app)
        reveal(dataTools, in: app)
        assertVisibleBounds(dataTools, in: app)
        dataTools.tap()
        let createBackup = app.buttons[arabic ? "إنشاء نسخة احتياطية مشفّرة" : "Create encrypted backup"]
        reveal(createBackup, in: app)
        assertVisibleBounds(createBackup, in: app)
        createBackup.tap()
        let password = app.secureTextFields["backupPassword"]
        reveal(password, in: app)
        assertVisibleBounds(password, in: app)
        capture(app, "16 backup tools landscape")
    }

    private func assertSelection(in app: XCUIApplication) {
        let count = element("selectedChequeCount", in: app)
        reveal(count, in: app)
        XCTAssertEqual(count.label, "1")
        let total = element("selectedChequeAmount", in: app)
        reveal(total, in: app)
        assertVisibleBounds(total, in: app)
        let westernDigits = total.label.filter { "0123456789".contains($0) }
        XCTAssertEqual(westernDigits, "123456789012", "The complete exact total must survive rotation and text enlargement")
        XCTAssertFalse(total.label.unicodeScalars.contains {
            (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value)
        })
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
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                picker.exists && ([picker.label, picker.value as? String ?? ""].joined(separator: " ")).contains(title)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                           "The menu must expose the chosen outgoing direction as its current value")
        }
    }

    private func rotate(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        rotateIPhone(to: orientation, in: app)
    }

    private func type(_ text: String, into field: XCUIElement, expected: String, in app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists && field.isEnabled && app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        field.typeText(text)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 5), .completed)
    }

    private func dismissKeyboard(in app: XCUIApplication, arabic: Bool) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons.matching(NSPredicate(format: "label == %@", arabic ? "تم" : "Done"))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(done, "A visible Done control must dismiss the numeric or text keyboard")
        done?.tap()
        waitForAbsence(app.keyboards.firstMatch)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func chequeRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", chequeNumber)).firstMatch
    }

    private func waitForAbsence(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
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

    /// Use measured navigation/keyboard/toolbars rather than portrait-only fixed top/bottom offsets.
    /// Content can be intentionally wider for the horizontally scrolling spreadsheet, but controls
    /// and accessibility cards still have to fit the viewport.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, allowHorizontalScroll: Bool = false) {
        let window = app.windows.firstMatch
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
            let targetFrame = target.exists ? target.frame : CGRect.null
            if target.exists {
                let fitsHeight = targetFrame.height <= bottom - top
                let verticallyVisible = fitsHeight ? targetFrame.minY >= top && targetFrame.maxY <= bottom :
                    targetFrame.midY >= top && targetFrame.midY <= bottom
                let horizontallyVisible = allowHorizontalScroll ||
                    (targetFrame.minX >= frame.minX - 1 && targetFrame.maxX <= frame.maxX + 1)
                // XCUITest can throw while resolving an offscreen button's activation point.
                // Check measured visibility first, scroll it into view, then require hittability.
                if verticallyVisible && horizontallyVisible && target.isHittable { return }
            }
            guard bottom > top + 24 else { break }
            let above = target.exists && targetFrame.height > 0 && targetFrame.minY < top
            let targetEdge = targetFrame.height > bottom - top ? targetFrame.midY : (above ? targetFrame.minY : targetFrame.maxY)
            let gap = target.exists ? (above ? top - targetEdge : targetEdge - bottom) : bottom - top
            let distance = min((bottom - top) * 0.65, max(24, gap * 0.75 + 8))
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let startY = above ? top + 4 : bottom - 4
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY + (above ? distance : -distance) - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        diagnostics(app, "Unreachable control " + target.identifier)
        XCTFail("Expected \(target.identifier) to be reachable inside the rotated viewport")
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
