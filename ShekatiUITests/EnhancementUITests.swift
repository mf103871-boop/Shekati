import XCTest

/// User-visible workflows use isolated memory and fictional records. No cloud/notification promise is inferred.
final class EnhancementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testConsecutiveEntryKeepsChosenDetailsClearsPrivateFieldsAndRequiresDateReview() {
        let app = launch()
        openEditor(app)
        app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].tap()
        fill(app, amount: "125.50", party: "Batch demo", number: "000201")
        setBank("Demo Batch Bank", in: app)
        hideKeyboard(in: app)
        let keep = app.switches["keepEntryDetails"]
        reveal(keep, in: app)
        keep.tap()
        XCTAssertEqual(keep.value as? String, "1")
        app.buttons["saveAndAddAnother"].tap()
        XCTAssertTrue(app.staticTexts["consecutiveChequeSaved"].waitForExistence(timeout: 8))
        hideKeyboard(in: app)
        XCTAssertTrue(isBlank(app.textFields["amountField"]))
        XCTAssertTrue(isBlank(app.textFields["chequeNumberField"]))
        XCTAssertEqual(app.textFields["partyField"].value as? String, "Batch demo")
        reveal(app.textFields["bankField"], in: app)
        XCTAssertEqual(app.textFields["bankField"].value as? String, "Demo Batch Bank")
        XCTAssertTrue(app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].isSelected)
        XCTAssertTrue(app.buttons["confirmNextChequeDate"].exists)
        capture(app, "Build 6 English consecutive entry requires a new due date")

        fillField("amountField", value: "40.00", in: app)
        fillField("chequeNumberField", value: "000202", in: app)
        hideKeyboard(in: app)
        app.buttons["saveCheque"].tap()
        XCTAssertTrue(app.buttons["saveCheque"].exists, "A new cheque must not save before its due date is reviewed")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Review the due date for the next cheque.")).firstMatch.exists)
        let confirmDate = app.buttons["confirmNextChequeDate"]
        reveal(confirmDate, in: app)
        confirmDate.tap()
        reveal(keep, in: app)
        keep.tap()
        XCTAssertEqual(keep.value as? String, "0")
        app.buttons["saveAndAddAnother"].tap()
        XCTAssertTrue(app.staticTexts["consecutiveChequeSaved"].waitForExistence(timeout: 8))
        hideKeyboard(in: app)
        XCTAssertTrue(isBlank(app.textFields["amountField"]))
        XCTAssertTrue(isBlank(app.textFields["chequeNumberField"]))
        XCTAssertTrue(isBlank(app.textFields["partyField"]))
        XCTAssertFalse(app.textFields["bankField"].exists)
        XCTAssertTrue(app.segmentedControls["chequeDirectionPicker"].buttons["Incoming"].isSelected)
        app.buttons["Cancel"].tap()
        waitForEditorDismissal(app)
        app.tabBars.buttons["Cheques"].tap()
        XCTAssertTrue(row(number: "000201", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(row(number: "000202", in: app).exists)
        capture(app, "Build 6 English two cheques saved consecutively")
    }

    func testDuplicateWarningLetsUserReviewExistingChequeOrExplicitlySaveAnother() {
        let app = launch()
        addCheque(app, amount: "125.50", party: "Duplicate demo", number: "000301", bank: "Demo Duplicate Bank")
        openEditor(app)
        fill(app, amount: "125.50", party: "Duplicate demo", number: "000301")
        setBank("Demo Duplicate Bank", in: app)
        hideKeyboard(in: app)
        app.buttons["saveCheque"].tap()
        let warning = app.alerts["Similar cheque found"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        capture(app, "Build 6 English probable duplicate warning")
        warning.buttons["View existing cheque"].tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["000301"].exists)
        XCTAssertTrue(app.buttons["closeDuplicatePreview"].exists)
        app.buttons["closeDuplicatePreview"].tap()
        XCTAssertTrue(app.buttons["saveCheque"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["chequeNumberField"].value as? String, "000301", "Review must preserve the unsaved draft")
        app.buttons["saveCheque"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["Save anyway"].tap()
        waitForEditorDismissal(app)
        app.tabBars.buttons["Cheques"].tap()
        XCTAssertEqual(rows(number: "000301", in: app).count, 2, "Explicit confirmation allows legitimate repeated records")
        capture(app, "Build 6 English explicitly confirmed repeated cheque")
    }

    func testPrimarySettlementRecordsActualDateAndMovesChequeOutOfOutstandingButKeepsHistory() {
        let app = launch()
        addCheque(app, amount: "130.50", party: "Payment demo", number: "000401", outgoing: true)
        app.tabBars.buttons["Cheques"].tap()
        let cheque = row(number: "000401", in: app)
        XCTAssertTrue(cheque.waitForExistence(timeout: 5))
        reveal(cheque, in: app)
        cheque.tap()
        XCTAssertFalse(app.staticTexts["Payment date"].exists)
        XCTAssertTrue(app.buttons["primarySettlement"].waitForExistence(timeout: 5))
        capture(app, "Build 6 English payment action next to amount")
        app.buttons["primarySettlement"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "actualSettlementDate").firstMatch.waitForExistence(timeout: 5))
        app.buttons["confirmSettlement"].tap()
        waitForAbsence(app.buttons["confirmSettlement"])
        XCTAssertTrue(app.staticTexts["Payment date"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["primarySettlement"].exists)
        capture(app, "Build 6 English actual payment date saved")
        goBack(in: app)
        XCTAssertTrue(app.navigationBars["Cheques"].waitForExistence(timeout: 5))
        waitForAbsence(row(number: "000401", in: app))
        app.segmentedControls["chequeHistoryScopePicker"].buttons["All and history"].tap()
        let history = row(number: "000401", in: app)
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(history.label.contains("Paid"))
        capture(app, "Build 6 English paid cheque retained in history")
    }

    func testSoftDeletionCanBeUndoneAndLaterRestoredFromSettingsTrash() {
        let app = launch()
        addCheque(app, amount: "150.00", party: "Restore demo", number: "000501")
        app.tabBars.buttons["Cheques"].tap()
        let cheque = row(number: "000501", in: app)
        XCTAssertTrue(cheque.waitForExistence(timeout: 5))
        reveal(cheque, in: app)
        cheque.tap()
        deleteCurrentCheque(in: app)
        capture(app, "Build 6 English deleted cheque can be undone")
        app.buttons["undoChequeDeletion"].tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["000501"].exists)
        goBack(in: app)
        XCTAssertTrue(cheque.waitForExistence(timeout: 5))
        reveal(cheque, in: app)
        cheque.tap()
        deleteCurrentCheque(in: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Cheques"].waitForExistence(timeout: 5))
        waitForAbsence(cheque)
        app.tabBars.buttons["Settings"].tap()
        let trash = app.descendants(matching: .any).matching(identifier: "recentlyDeleted").firstMatch
        reveal(trash, in: app)
        trash.tap()
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restore-")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        reveal(restore, in: app)
        capture(app, "Build 6 English recently deleted cheque retains its details")
        restore.tap()
        XCTAssertTrue(app.staticTexts["No deleted cheques"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Cheques"].tap()
        XCTAssertTrue(cheque.waitForExistence(timeout: 5))
        XCTAssertTrue(cheque.label.contains("150"))
        capture(app, "Build 6 English cheque restored from recently deleted")
    }

    func testArabicAmountErrorAndQuickPeriodsKeepFilteringClearAndReversible() {
        let app = launch(arabic: true)
        openEditor(app)
        fillField("amountField", value: "0", in: app)
        app.buttons["saveCheque"].tap()
        XCTAssertTrue(app.staticTexts["amountValidationError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCheque"].exists)
        capture(app, "Build 6 Arabic amount error beside the field")
        let amount = app.textFields["amountField"]
        amount.tap()
        amount.typeText(XCUIKeyboardKey.delete.rawValue + "175.50")
        fillField("partyField", value: "Arabic due today demo", in: app)
        fillField("chequeNumberField", value: "000601", in: app)
        hideKeyboard(in: app, arabic: true)
        app.buttons["saveCheque"].tap()
        waitForEditorDismissal(app)
        app.tabBars.buttons["الشيكات"].tap()
        XCTAssertTrue(row(number: "000601", in: app).waitForExistence(timeout: 5))
        app.buttons["period-today"].tap()
        XCTAssertTrue(row(number: "000601", in: app).exists)
        XCTAssertTrue(app.buttons["clearActiveFilters"].exists)
        app.segmentedControls["listDirectionPicker"].buttons["صادر"].tap()
        waitForAbsence(row(number: "000601", in: app))
        app.buttons["clearActiveFilters"].tap()
        XCTAssertTrue(row(number: "000601", in: app).waitForExistence(timeout: 5))
        capture(app, "Build 6 Arabic outstanding cheques and quick periods")
    }

    private func launch(arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (arabic ? ["--arabic"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["chooseCurrency"].waitForExistence(timeout: 10))
        reveal(app.buttons["chooseCurrency"], in: app)
        app.buttons["chooseCurrency"].tap()
        XCTAssertTrue(app.buttons["currency_USD"].waitForExistence(timeout: 5))
        app.buttons["currency_USD"].tap()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 5))
        return app
    }

    private func openEditor(_ app: XCUIApplication) {
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
    }

    private func addCheque(_ app: XCUIApplication, amount: String, party: String, number: String,
                           bank: String? = nil, outgoing: Bool = false) {
        openEditor(app)
        if outgoing { app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].tap() }
        fill(app, amount: amount, party: party, number: number)
        if let bank { setBank(bank, in: app) }
        hideKeyboard(in: app)
        app.buttons["saveCheque"].tap()
        waitForEditorDismissal(app)
    }

    private func fill(_ app: XCUIApplication, amount: String, party: String, number: String) {
        fillField("amountField", value: amount, in: app)
        fillField("partyField", value: party, in: app)
        fillField("chequeNumberField", value: number, in: app)
    }

    private func fillField(_ identifier: String, value: String, in app: XCUIApplication) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(field, in: app)
        field.tap()
        field.typeText(value)
    }

    private func setBank(_ value: String, in app: XCUIApplication) {
        hideKeyboard(in: app)
        if !app.textFields["bankField"].exists {
            let details = app.buttons["More details"]
            reveal(details, in: app)
            details.tap()
        }
        fillField("bankField", value: value, in: app)
    }

    private func hideKeyboard(in app: XCUIApplication, arabic: Bool = false) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons[arabic ? "تم" : "Done"].firstMatch
        if done.exists && done.isHittable { done.tap() }
    }

    private func isBlank(_ field: XCUIElement) -> Bool {
        let value = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        return value.isEmpty || value == placeholder
    }

    private func rows(number: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", number))
    }

    private func row(number: String, in app: XCUIApplication) -> XCUIElement { rows(number: number, in: app).firstMatch }

    private func waitForEditorDismissal(_ app: XCUIApplication) { waitForAbsence(app.buttons["saveCheque"]) }

    private func waitForAbsence(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func deleteCurrentCheque(in app: XCUIApplication) {
        let delete = app.buttons["Delete cheque"]
        reveal(delete, in: app)
        delete.tap()
        let alert = app.alerts["Delete this cheque?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["undoChequeDeletion"].waitForExistence(timeout: 5))
    }

    private func goBack(in app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let leftmost = bar.buttons.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        XCTAssertNotNil(leftmost)
        leftmost?.tap()
    }

    /// Coordinate scrolling stays above the keyboard and below the active navigation bar.
    /// It supports both lower Settings rows and fields temporarily above the current scroll position.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.isHittable { return }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        for _ in 0..<12 {
            if element.isHittable { return }
            let frame = window.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = keyboard.exists && keyboard.frame.height > 0
            let predictions = app.otherElements["Typing Predictions"].firstMatch
            let keyboardTop = keyboardVisible ? keyboard.frame.minY : frame.maxY
            let accessoryTop = keyboardVisible ?
                (predictions.exists && predictions.frame.height > 0 ? predictions.frame.minY : keyboardTop - 60) : keyboardTop
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let bottom = min(frame.maxY - 85, min(keyboardTop, accessoryTop)) - 24
            guard bottom > top + 50 else { break }
            let distance = min(220, (bottom - top) * 0.65)
            let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let above = element.exists && element.frame.height > 0 && element.frame.maxY < top
            let startY = above ? top + 15 : bottom
            let endY = above ? startY + distance : startY - distance
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: endY - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !element.isHittable {
            capture(app, "Build 6 enhancement field remained offscreen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Build 6 enhancement accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(element.isHittable, "Expected the control to become visible")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
