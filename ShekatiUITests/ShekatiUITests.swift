import XCTest

final class ShekatiUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(arabic: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (arabic ? ["--arabic"] : [])
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["chooseCurrency"].waitForExistence(timeout: 10))
        reveal(app.buttons["chooseCurrency"], in: app)
        app.buttons["chooseCurrency"].tap()
        XCTAssertTrue(app.buttons["currency_USD"].waitForExistence(timeout: 5))
        app.buttons["currency_USD"].tap()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 5))
        return app
    }

    func testAddChequePreservesLeadingZerosAndAppearsInList() {
        let app = launch()
        app.buttons["addCheque"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.isHittable)
        XCTAssertTrue(app.textFields["partyField"].isHittable)
        XCTAssertTrue(app.textFields["chequeNumberField"].isHittable)
        XCTAssertFalse(app.textFields["bankField"].exists)
        captureScreenshot(app, name: "English quick cheque entry")
        selectOutgoing(in: app)
        amount.tap()
        amount.typeText("125.50")
        let number = app.textFields["chequeNumberField"]
        reveal(number, in: app)
        number.tap()
        number.typeText("000182")
        let party = app.textFields["partyField"]
        reveal(party, in: app, searchEarlierIfAbsent: true)
        party.tap()
        party.typeText("CI cheque")
        let details = app.buttons["More details"]
        reveal(details, in: app)
        details.tap()
        let bank = app.textFields["bankField"]
        reveal(bank, in: app)
        XCTAssertTrue(bank.exists)
        bank.tap()
        bank.typeText("Demo Bank")
        app.buttons["saveCheque"].tap()
        allowNotificationPromptIfPresented()
        waitForEditorDismissal(in: app)
        app.tabBars.buttons["Cheques"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "cheque-row-", "CI cheque", "000182"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("CI cheque"))
        XCTAssertTrue(row.label.contains("000182"))
        XCTAssertTrue(app.staticTexts["outgoingTableTitle"].exists)
        XCTAssertLessThan(app.staticTexts["Value"].frame.midX, app.windows.firstMatch.frame.midX,
                          "English sheet starts with the value column on the left")
        reveal(row, in: app)
        captureScreenshot(app, name: "English compact cheque table")
        row.tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["000182"].exists)
        captureScreenshot(app, name: "English cheque details — leading zeros preserved")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["bankField"].waitForExistence(timeout: 5),
                      "Existing optional details should expand when editing")
        XCTAssertEqual(app.textFields["bankField"].value as? String, "Demo Bank")
        XCTAssertEqual(app.textFields["chequeNumberField"].value as? String, "000182")
        app.buttons["Cancel"].tap()
    }

    func testArabicQuickEntryAndOutgoingSheetListsOnlyOutgoingCheques() {
        let app = launch(arabic: true)
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["partyField"].isHittable)
        XCTAssertTrue(app.textFields["chequeNumberField"].isHittable)
        XCTAssertFalse(app.textFields["bankField"].exists)
        XCTAssertGreaterThan(app.staticTexts["المبلغ"].frame.midX, app.windows.firstMatch.frame.midX,
                             "Arabic entry labels must use a right-to-left Form")
        XCTAssertLessThan(app.buttons["saveCheque"].frame.midX, app.windows.firstMatch.frame.midX,
                          "Arabic Save must use the trailing side of a right-to-left navigation bar")
        captureScreenshot(app, name: "Arabic quick cheque entry")
        fillQuickCheque(in: app, amount: "125.50", party: "Demo incoming", number: "000101")
        app.buttons["saveCheque"].tap()
        allowNotificationPromptIfPresented()
        waitForEditorDismissal(in: app)
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        selectOutgoing(in: app, arabic: true)
        fillQuickCheque(in: app, amount: "760.00", party: "Demo outgoing", number: "000102")
        app.buttons["saveCheque"].tap()
        allowNotificationPromptIfPresented()
        waitForEditorDismissal(in: app)
        captureScreenshot(app, name: "Arabic simple home with cheques")
        app.tabBars.buttons["الشيكات"].tap()
        let incoming = chequeRow(in: app, named: "Demo incoming")
        let outgoing = chequeRow(in: app, named: "Demo outgoing")
        XCTAssertTrue(outgoing.waitForExistence(timeout: 5))
        XCTAssertTrue(outgoing.label.contains("000102"))
        XCTAssertTrue(outgoing.label.contains("760"), "The sheet shows plain amounts such as 760")
        XCTAssertFalse(incoming.exists, "The cheques sheet lists outgoing cheques only")
        let title = app.staticTexts["outgoingTableTitle"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "شيكات مؤجلة")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(app.staticTexts["القيمة"].frame.midX, window.midX,
                             "Arabic sheet starts with the value column on the right")
        captureScreenshot(app, name: "Arabic outgoing cheques sheet — leading columns")
        revealSheetHeading(app.staticTexts["رصيد"], arabic: true, in: app)
        XCTAssertLessThan(app.staticTexts["رصيد"].frame.midX, window.midX,
                          "Arabic sheet ends with the balance column on the left")
        captureScreenshot(app, name: "Arabic outgoing cheques sheet — balance reached by horizontal scrolling")
    }

    private func fillQuickCheque(in app: XCUIApplication, amount: String, party: String, number: String) {
        for (index, entry) in [("amountField", amount), ("partyField", party), ("chequeNumberField", number)].enumerated() {
            let (identifier, text) = entry
            let field = app.textFields[identifier]
            if index == 0 {
                reveal(field, in: app)
                field.tap()
            } else {
                // Exercise the app's accepted keyboard navigation. SwiftUI materializes and focuses
                // the next field even when its Form cell is outside the accessibility snapshot.
                let next = app.buttons["Next"].exists ? app.buttons["Next"] : app.buttons["التالي"]
                XCTAssertTrue(next.waitForExistence(timeout: 5))
                next.tap()
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                field.exists && field.isEnabled && app.keyboards.firstMatch.exists
            }, object: field)
            let result = XCTWaiter.wait(for: [ready], timeout: 5)
            if result != .completed { captureDiagnostics(app, name: "Input or keyboard was not ready") }
            XCTAssertEqual(result, .completed, "Expected the target field and keyboard to be ready before typing")
            let value = (field.value as? String) ?? ""
            let existing = value == field.placeholderValue ? "" : value
            // Do not retap after Next. typeText requires real keyboard focus, and the exact
            // target value below proves the navigation delivered input to the intended field.
            field.typeText(text)
            let received = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", existing + text),
                                                     object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 5), .completed,
                           "The field reached by keyboard navigation must receive exactly the supplied text")
        }
    }

    func testLargeTextKeepsChequeRowReadableAndNavigable() {
        let app = launch(largeText: true)
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        selectOutgoing(in: app)
        fillQuickCheque(in: app, amount: "9999.50", party: "Large text demo", number: "000999")
        app.buttons["saveCheque"].tap()
        allowNotificationPromptIfPresented()
        waitForEditorDismissal(in: app)
        app.tabBars.buttons["Cheques"].tap()
        let row = chequeRow(in: app, named: "Large text demo")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("000999"))
        reveal(row, in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(row.isHittable)
        // Accessibility text uses readable cards; no part of a card may extend outside the screen.
        XCTAssertGreaterThanOrEqual(row.frame.minX, window.minX - 1)
        XCTAssertLessThanOrEqual(row.frame.maxX, window.maxX + 1)
        XCTAssertGreaterThan(row.frame.width, window.width * 0.9)
        captureScreenshot(app, name: "Accessibility large text cheque table")
        row.tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
    }

    private func chequeRow(in app: XCUIApplication, named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", name
        )).firstMatch
    }

    private func selectOutgoing(in app: XCUIApplication, arabic: Bool = false) {
        let title = arabic ? "صادر" : "Outgoing"
        let segmented = app.segmentedControls["chequeDirectionPicker"]
        if segmented.exists {
            let option = segmented.buttons[title]
            reveal(option, in: app)
            option.tap()
            XCTAssertTrue(option.isSelected)
        } else {
            let picker = app.descendants(matching: .any).matching(identifier: "chequeDirectionPicker").firstMatch
            reveal(picker, in: app)
            picker.tap()
            let option = app.buttons[title].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5) && option.isHittable)
            option.tap()
            let selectedPicker = app.buttons.matching(identifier: "chequeDirectionPicker")
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title)).firstMatch
            let selected = selectedPicker.waitForExistence(timeout: 10)
            if !selected { captureDiagnostics(app, name: "Direction menu did not expose the chosen outgoing value") }
            XCTAssertTrue(selected, "The accessibility menu must expose its selected outgoing value")
        }
    }

    private func revealSheetHeading(_ heading: XCUIElement, arabic: Bool, in app: XCUIApplication) {
        let table = app.descendants(matching: .any).matching(identifier: "outgoingChequeTable").firstMatch
        let window = app.windows.firstMatch.frame
        for _ in 0..<5 {
            if heading.exists {
                let frame = heading.frame
                // iOS 26 can throw resolving an activation point for a column outside
                // the horizontal viewport. Pan first, then require a real visible hit point.
                if frame.width > 0 && frame.height > 0 &&
                    frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1 &&
                    frame.minY >= window.minY - 1 && frame.maxY <= window.maxY + 1 &&
                    heading.isHittable { return }
            }
            // In Arabic the last column sits to the left; drag the sheet right to reveal it.
            if arabic { table.swipeRight() } else { table.swipeLeft() }
        }
        captureDiagnostics(app, name: "Spreadsheet trailing column could not be reached")
        XCTFail("Horizontal scrolling must expose the complete trailing heading")
    }

    private func waitForEditorDismissal(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.buttons["saveCheque"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
    }

    func testArabicFirstRunAndEnglishLanguageSwitch() {
        let app = launch(arabic: true)
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].exists)
        captureScreenshot(app, name: "Arabic home")
        app.tabBars.buttons["الإعدادات"].tap()
        let language = app.descendants(matching: .any).matching(identifier: "languagePicker").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance and language"].exists || app.staticTexts["APPEARANCE AND LANGUAGE"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        waitForStableEnglishSettingsLayout(in: app)
        captureScreenshot(app, name: "English settings after language switch")
    }

    private func waitForStableEnglishSettingsLayout(in app: XCUIApplication) {
        let brand = app.staticTexts["settingsBrandTitle"]
        var previousFrame = CGRect.null
        var stableSince: Date?
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard brand.exists, brand.isHittable else {
                stableSince = nil
                return false
            }
            let frame = brand.frame
            // Arabic places the brand text on the right. English must rebuild on the left,
            // rather than leaving translated text inside the old mirrored Form container.
            guard frame.width > 0, frame.midX < app.windows.firstMatch.frame.midX else {
                stableSince = nil
                return false
            }
            if frame != previousFrame || stableSince == nil {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince!) >= 0.6
        }, object: brand)
        let result = XCTWaiter.wait(for: [layout], timeout: 8)
        if result != .completed { captureDiagnostics(app, name: "English Settings layout did not settle") }
        XCTAssertEqual(result, .completed, "Expected stable left-to-right English Settings layout")
    }

    /// Container hit-testing can be false while its fields remain interactive on iOS 26.
    /// Use window coordinates bounded by the active navigation bar and software keyboard instead.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, searchEarlierIfAbsent: Bool = false) {
        let window = app.windows.firstMatch
        var searchEarlier = searchEarlierIfAbsent
        guard window.exists else {
            captureDiagnostics(app, name: "No app window while revealing field")
            XCTFail("Expected the app window to exist")
            return
        }
        for _ in 0..<12 {
            let frame = window.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = keyboard.exists && keyboard.frame.height > 0
            let keyboardTop = keyboardVisible ? keyboard.frame.minY : frame.maxY
            // Native iOS 26 evidence: Keyboard.frame starts at 611, but Typing Predictions starts at 567.
            // Respect the separate accessory element; keep a conservative inset when it isn't exposed.
            let predictions = app.otherElements["Typing Predictions"].firstMatch
            let accessoryTop = keyboardVisible ?
                (predictions.exists && predictions.frame.height > 0 ? predictions.frame.minY : keyboardTop - 60) : keyboardTop
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.compactMap { bar -> CGFloat? in
                guard bar.exists else { return nil }
                let barFrame = bar.frame
                guard barFrame.height > 0, barFrame.intersects(frame) else { return nil }
                return barFrame.maxY
            }.max() ?? frame.minY + 100
            let visibleTop = max(frame.minY + 100, navigationBottom + 8)
            let toolbarTop = app.toolbars.allElementsBoundByIndex.compactMap { toolbar -> CGFloat? in
                guard toolbar.exists else { return nil }
                let toolbarFrame = toolbar.frame
                guard toolbarFrame.height > 0, toolbarFrame.intersects(frame), toolbarFrame.minY > visibleTop else { return nil }
                return toolbarFrame.minY
            }.min() ?? frame.maxY
            let tabBar = app.tabBars.firstMatch
            let tabBarTop = tabBar.exists && tabBar.frame.height > 0 && tabBar.frame.intersects(frame) ?
                tabBar.frame.minY : frame.maxY
            let visibleBottom = min(frame.maxY - 34, min(tabBarTop, min(toolbarTop, min(keyboardTop, accessoryTop)))) - 8
            guard visibleBottom > visibleTop + 40 else {
                captureDiagnostics(app, name: "Insufficient visible scroll area")
                XCTFail("The visible scroll area is too small to reveal the field")
                return
            }
            let targetExists = element.exists
            let targetFrame = targetExists ? element.frame : CGRect.null
            if targetExists {
                let centerInside = targetFrame.midY >= visibleTop && targetFrame.midY <= visibleBottom
                let fullFrameInside = targetFrame.minY >= visibleTop && targetFrame.maxY <= visibleBottom
                let visibleTarget = element.identifier.hasPrefix("cheque-row-") ? centerInside : fullFrameInside
                if visibleTarget && element.isHittable { return }
            }
            let requireFullFrame = targetExists && !element.identifier.hasPrefix("cheque-row-")
            let targetTop = requireFullFrame ? targetFrame.minY : targetFrame.midY
            let targetBottom = requireFullFrame ? targetFrame.maxY : targetFrame.midY
            if targetExists && targetFrame.height > 0 { searchEarlier = targetTop < visibleTop }
            let above = searchEarlier
            let delta = targetExists && targetFrame.height > 0 ?
                (above ? visibleTop - targetTop : targetBottom - visibleBottom) : 100
            let distance = targetExists && targetFrame.height > 0 ?
                min(min(140, (visibleBottom - visibleTop) * 0.4), max(24, delta * 0.7 + 12)) : (visibleBottom - visibleTop) * 0.65
            let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let startY = above ? visibleTop + 15 : visibleBottom
            let endY = above ? startY + distance : startY - distance
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: endY - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        captureDiagnostics(app, name: "Field remained offscreen after scrolling")
        XCTFail("Expected the field or cheque row to become visible after scrolling")
    }

    private func captureDiagnostics(_ app: XCUIApplication, name: String) {
        captureScreenshot(app, name: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " — accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func captureScreenshot(_ app: XCUIApplication, name: String) {
        attachNativeScreenshot(in: app, name: name)
    }

    private func allowNotificationPromptIfPresented() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            let allow = alert.buttons["Allow"]
            let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            guard allow.exists && text.localizedCaseInsensitiveContains("notification") else {
                captureDiagnostics(springboard, name: "Unexpected system alert after save")
                XCTFail("Expected an Allow button on the system notification prompt")
                return
            }
            allow.tap()
        }
    }
}
