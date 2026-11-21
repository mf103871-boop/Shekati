import XCTest
import UIKit

/// Optical recognition runs on the same Vision path used after scanning a cheque on a phone.
final class StoreScreenshotUITests: XCTestCase {
    func testUpcomingChequesAppearInDueOrderBetweenShortfallAndForecast() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--store-screens", "-ShekatiStoreLocale", "en-US",
                               "-shekati.hideAmounts", "NO"]
        app.launch()

        let shortfall = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shortfallDetails")).firstMatch
        let forecast = app.staticTexts["dashboardForecastTitle"]
        // The saved cheques are due today, then in five, six and seven days, across both directions.
        let numbers = ["004182", "007309", "007310", "004185"]
        func cheque(_ number: String) -> XCUIElement {
            app.buttons["cheque-row-00000000-0000-4000-8000-000000" + number]
        }
        let landmarks = [shortfall, app.staticTexts["dashboardUpcomingTitle"]] + numbers.map(cheque) + [forecast]
        var previousBottom = CGFloat.zero
        for element in landmarks {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing dashboard element: \(element)")
            let frame = element.frame
            XCTAssertFalse(frame.isEmpty)
            XCTAssertTrue(frame.minY.isFinite && frame.maxY.isFinite)
            XCTAssertGreaterThanOrEqual(frame.minY, previousBottom, "Dashboard element out of order: \(element.label)")
            previousBottom = frame.maxY
        }
        XCTAssertTrue(shortfall.label.contains("650.000"))
        XCTAssertFalse(cheque("007311").exists, "The fifth, later cheque belongs in the full register.")
        for _ in 0..<5 where !forecast.isHittable { app.swipeUp() }
        XCTAssertTrue(forecast.isHittable, "The forecast must be reachable below the upcoming cheques.")
    }

    func testPartialCashSettlementUpdatesHomeAndOutgoingRegister() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--store-screens", "-ShekatiStoreLocale", "en-US"]
        app.launch()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 12))
        let homeDue = app.descendants(matching: .any).matching(identifier: "outgoingDueAmount").firstMatch
        XCTAssertTrue(homeDue.label.contains("3,200.000"))
        nativeTab(.cheques, in: app).tap()
        let row = app.descendants(matching: .any).matching(identifier:
            "cheque-row-00000000-0000-4000-8000-000000007309").firstMatch
        for _ in 0..<7 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        row.tap()
        let otherActions = app.buttons["moreChequeActions"]
        for _ in 0..<7 where !otherActions.isHittable { app.swipeUp() }
        XCTAssertTrue(otherActions.isHittable)
        otherActions.tap()
        let partial = app.buttons["operation-partialCash"].exists ? app.buttons["operation-partialCash"] : app.buttons["Partial cash payment"]
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        XCTAssertTrue(partial.isHittable)
        partial.tap()
        let amount = app.textFields.firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("150")
        let review = app.buttons["reviewOperation"]
        for _ in 0..<5 where !review.isHittable { app.swipeUp() }
        review.tap()
        let confirm = app.buttons.matching(identifier: "commitOperation").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        nativeTab(.home, in: app).tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "3,050.000"), object: homeDue)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        openMoreDestination("outgoingLedgerLink", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("1650"), "The outgoing register's amount must show the remaining 1,650 after the 150 cash payment.")
    }

    func testLocalizedProductScreens() throws {
        continueAfterFailure = false
        guard let locale = ProcessInfo.processInfo.environment["SHEKATI_STORE_LOCALE"], !locale.isEmpty else {
            throw XCTSkip("The store capture workflow supplies an App Store locale.")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--store-screens", "-ShekatiStoreLocale", locale,
                               "-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        app.launch()
        func element(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func capture(_ screen: String) {
            attachNativeScreenshot(in: app, name: "Store-\(locale)-\(screen)")
        }
        let homeBalance = element("outgoingDueAmount")
        func waitForDestination(_ identifier: String, leaving previous: XCUIElement) {
            let marker = element(identifier)
            XCTAssertTrue(marker.waitForExistence(timeout: 12), "Missing destination landmark \(identifier)")
            let previousLeft = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: previous)
            XCTAssertEqual(XCTWaiter.wait(for: [previousLeft], timeout: 12), .completed,
                           "The previous content must leave the screen before capturing \(identifier)")
            XCTAssertTrue(marker.isHittable, "The destination landmark \(identifier) must be visible")
        }
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 15))
        XCTAssertTrue(homeBalance.waitForExistence(timeout: 10))
        capture("01-home")

        // The simulator fixture uses today's date at launch. Capture the calendar and
        // register in the same session so midnight cannot create two different due dates.
        let row = element("cheque-row-00000000-0000-4000-8000-000000004182")
        let calendar = nativeTab(.calendar, in: app)
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        waitForDestination("calendarNextMonth", leaving: homeBalance)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let calendarRow = row.label
        XCTAssertTrue(calendarRow.contains("004182"))
        capture("05-calendar")

        let ledger = nativeTab(.cheques, in: app)
        XCTAssertTrue(ledger.waitForExistence(timeout: 5))
        ledger.tap()
        waitForDestination("shownChequeCount", leaving: element("calendarNextMonth"))
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertEqual(row.label, calendarRow, "The same cheque must expose the same amount, due date and state on both screens.")
        capture("02-ledger")
        row.tap()
        let edit = app.buttons["editCheque"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        capture("04-detail")
        edit.tap()

        let resources = Bundle(for: type(of: self))
        let translationPath = try XCTUnwrap(resources.path(forResource: locale, ofType: "lproj"))
        let translations = try XCTUnwrap(Bundle(path: translationPath))
        let done = translations.localizedString(forKey: "Done", value: nil, table: nil)
        let finishTyping = app.toolbars.buttons.matching(NSPredicate(format: "label == %@", done)).firstMatch
        let amount = app.textFields["amountField"]
        if locale == "nl" {
            for _ in 0..<6 where !amount.isHittable { app.swipeUp() }
            XCTAssertTrue(amount.isHittable)
            XCTAssertEqual(amount.value as? String, "1250.000")
            // Put the caret at the end of the right-aligned amount and change one JOD fils.
            amount.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            amount.typeText(XCUIKeyboardKey.delete.rawValue + "1")
            XCTAssertEqual(amount.value as? String, "1250.001")
            XCTAssertTrue(finishTyping.waitForExistence(timeout: 8) && finishTyping.isHittable)
            finishTyping.tap()
        }
        let numberField = app.textFields["chequeNumberField"]
        for _ in 0..<8 where !numberField.isHittable { app.swipeUp() }
        XCTAssertEqual(numberField.value as? String, "004182")
        numberField.tap()
        numberField.typeText("9")
        let edited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "9"), object: numberField)
        XCTAssertEqual(XCTWaiter.wait(for: [edited], timeout: 8), .completed)
        XCTAssertTrue(finishTyping.waitForExistence(timeout: 8) && finishTyping.isHittable)
        finishTyping.tap()

        let scan = app.buttons["readChequeImage"]
        let numberChoice = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "004182")).firstMatch
        func openReview() {
            for _ in 0..<12 where !scan.isHittable { app.swipeUp() }
            XCTAssertTrue(scan.isHittable)
            scan.tap()
            XCTAssertTrue(numberChoice.waitForExistence(timeout: 90),
                          "Vision must open the recognized number. " + app.debugDescription)
            XCTAssertEqual(numberChoice.value as? String, "1", "The recognized number must be selected.")
        }
        openReview()
        let use = app.buttons.matching(identifier: "useOCRFields").firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 8))
        XCTAssertTrue(use.isEnabled && use.isHittable)
        XCTAssertEqual(use.label, translations.localizedString(forKey: "Use selected", value: nil, table: nil))
        XCTAssertGreaterThanOrEqual(use.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(use.frame))
        if locale == "nl" {
            // On this device the previous toolbar overflow swallowed the only action.
            // Scroll across every fixture switch while keeping the single footer action visible.
            for field in ["number", "bank", "party", "amount", "dueDate"] {
                let choice = app.switches.matching(identifier: "ocr-field-" + field).firstMatch
                revealRecognizedSwitch(choice, above: use, in: app, movingDown: true)
                XCTAssertEqual(choice.value as? String, "1", field)
                tapRecognizedFieldSwitch(choice, expected: "0")
            }
            XCTAssertFalse(use.isEnabled)
            attachNativeScreenshot(in: app, name: "QA-NL-OCR-none")
            revealRecognizedSwitch(numberChoice, above: use, in: app, movingDown: false)
            tapRecognizedFieldSwitch(numberChoice, expected: "1")
            XCTAssertTrue(use.isEnabled && use.isHittable)
            attachNativeScreenshot(in: app, name: "QA-NL-OCR-number")
        }
        use.tap()
        // Verify the action's effect in the editor. Nothing is saved to the cheque.
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: numberChoice)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        for _ in 0..<10 where !amount.isHittable { app.swipeDown() }
        XCTAssertEqual(amount.value as? String, locale == "nl" ? "1250.001" : "1250.000",
                       "Applying the selected fields must preserve a manually edited, unselected JOD amount.")
        if locale == "nl" { attachNativeScreenshot(in: app, name: "QA-NL-OCR-draft") }
        for _ in 0..<8 where !numberField.exists { app.swipeUp() }
        XCTAssertEqual(numberField.value as? String, "004182",
                       "Using the selected fields must replace the deliberately changed draft number with the scanned number.")
        // Start the actual screenshot from a freshly opened, unmodified review presentation.
        openReview()
        capture("03-review")
        let amountChoice = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "1250.000")).firstMatch
        for _ in 0..<4 where !amountChoice.exists { app.swipeUp() }
        XCTAssertTrue(amountChoice.exists, "The review must contain the fixture amount recognized by Vision.")
        XCTAssertEqual(amountChoice.value as? String, "1")

    }

    func testArabicOCRSelectionRemainsVisibleInDarkMode() {
        exerciseArabicDarkScan(largeText: false)
    }

    func testArabicLargeTextOCRFooterInPortraitAndLandscape() {
        exerciseArabicDarkScan(largeText: true)
    }

    private func exerciseArabicDarkScan(largeText: Bool) {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        XCUIDevice.shared.orientation = .portrait
        defer {
            XCUIDevice.shared.appearance = previous
            XCUIDevice.shared.orientation = .portrait
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--store-screens", "-ShekatiStoreLocale", "ar",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar", "-appearance", "dark"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launch()
        let ledger = nativeTab(.cheques, in: app)
        XCTAssertTrue(ledger.waitForExistence(timeout: 12))
        ledger.tap()
        let row = app.descendants(matching: .any).matching(identifier: "cheque-row-00000000-0000-4000-8000-000000004182").firstMatch
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, app.debugDescription)
        row.tap()
        let edit = app.buttons["editCheque"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let scan = app.buttons["readChequeImage"]
        for _ in 0..<16 where !scan.isHittable { app.swipeUp() }
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        let use = app.buttons.matching(identifier: "useOCRFields").firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 90))
        XCTAssertTrue(use.isEnabled && use.isHittable)
        XCTAssertGreaterThanOrEqual(use.frame.height, 44)
        if largeText {
            let due = app.switches.matching(identifier: "ocr-field-dueDate").firstMatch
            for (orientation, suffix) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
                rotateIPhone(to: orientation, in: app)
                XCTAssertTrue(use.isEnabled && use.isHittable)
                XCTAssertTrue(app.windows.firstMatch.frame.contains(use.frame))
                XCTAssertGreaterThanOrEqual(use.frame.height, 44)
                attachNativeScreenshot(in: app, name: "OCR-Arabic-large-" + suffix + "-footer")
                for _ in 0..<10 {
                    if due.exists && due.isHittable && due.frame.maxY <= use.frame.minY { break }
                    if due.exists && due.frame.midY < 0 { app.swipeDown() } else { app.swipeUp() }
                }
                XCTAssertTrue(due.isHittable, due.debugDescription)
                XCTAssertLessThanOrEqual(due.frame.maxY, use.frame.minY, "The fixed action must not cover the last recognized field.")
                XCTAssertEqual(due.value as? String, "1")
                tapRecognizedFieldSwitch(due, expected: "0")
                tapRecognizedFieldSwitch(due, expected: "1")
                attachNativeScreenshot(in: app, name: "OCR-Arabic-large-" + suffix + "-last-field")
            }
        } else {
            attachNativeScreenshot(in: app, name: "OCR-Arabic-dark-selected-fields")
        }
        use.tap()
        XCTAssertTrue(app.buttons["readChequeImage"].waitForExistence(timeout: 8))
        XCTAssertFalse(use.exists)
    }

    private func revealRecognizedSwitch(_ row: XCUIElement, above footer: XCUIElement,
                                        in app: XCUIApplication, movingDown: Bool) {
        let control = row.switches.firstMatch
        for _ in 0..<6 {
            if control.exists && control.isHittable && control.frame.maxY <= footer.frame.minY { return }
            if movingDown { app.swipeUp() } else { app.swipeDown() }
        }
        XCTFail("The native switch must be fully reachable above the fixed button: " + row.debugDescription)
    }

    private func tapRecognizedFieldSwitch(_ row: XCUIElement, expected: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI exposes a labeled switch row with selectable text, and a native
        // UISwitch at its trailing edge. Tap the control surfaced by UIKit, in either layout direction.
        XCTAssertFalse(row.label.isEmpty, file: file, line: line)
        let control = row.switches.firstMatch
        guard control.exists && control.isHittable else {
            XCTFail("Missing hittable native switch: " + row.debugDescription, file: file, line: line)
            return
        }
        control.tap()
        let change = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            row.value as? String == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [change], timeout: 8), .completed,
                       "The native switch must update its labeled accessibility state after one tap",
                       file: file, line: line)
    }
}
