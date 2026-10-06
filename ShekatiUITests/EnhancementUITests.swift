import XCTest
import UIKit

/// User-visible workflows use isolated memory and fictional records. No cloud/notification promise is inferred.
final class EnhancementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testArabicNumericFieldsNormalizePastedDigitsAndRejectLettersSymbolsAndExcessPrecision() {
        let app = launch(arabic: true)
        openEditor(app)
        app.segmentedControls["chequeDirectionPicker"].buttons["صادر"].tap()

        let amount = app.textFields["amountField"]
        paste("١٢٥٫٥٠", into: amount, in: app)
        assertValue("125.50", in: amount)
        paste("ABC#", into: amount, in: app)
        assertValue("125.50", in: amount)
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        amount.typeText("9")
        assertValue("125.50", in: amount) // USD must not silently round a third fractional digit.

        fillField("partyField", value: "Numeric input demo", in: app)
        hideKeyboard(in: app, arabic: true)
        let number = app.textFields["chequeNumberField"]
        paste("٠٠٠٨١٢", into: number, in: app)
        assertValue("000812", in: number)
        paste("ABC#.", into: number, in: app)
        assertValue("000812", in: number)
        hideKeyboard(in: app, arabic: true)

        let date = app.descendants(matching: .any).matching(identifier: "dueDateField").firstMatch
        XCTAssertTrue(date.exists)
        let pickerText = ([date] + date.descendants(matching: .any).allElementsBoundByIndex)
            .map { $0.label + " " + (($0.value as? String) ?? "") }.joined(separator: " ")
        XCTAssertFalse(pickerText.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) ||
            (0x06F0...0x06F9).contains($0.value) }, "Date controls must use English digits in the Arabic interface")
        capture(app, "Arabic numeric entry keeps leading zeros and English digits")
        app.buttons["saveCheque"].tap()
        waitForEditorDismissal(app)
        app.tabBars.buttons["الشيكات"].tap()
        let saved = row(number: "000812", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.label.contains("125.5"))
        reveal(saved, in: app)
        saved.tap()
        app.buttons["تعديل"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        assertValue("125.50", in: amount)
        assertValue("000812", in: number)
    }

    func testConsecutiveEntryKeepsChosenDetailsClearsPrivateFieldsAndRequiresDateReview() {
        let app = launch()
        openEditor(app)
        app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].tap()
        fill(app, amount: "125.50", party: "Batch demo", number: "000201")
        setBank("Demo Batch Bank", in: app)
        hideKeyboard(in: app)
        let keep = app.switches["keepEntryDetails"]
        setSwitch(keep, enabled: true, in: app)
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
        setSwitch(keep, enabled: false, in: app)
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
        addCheque(app, amount: "125.50", party: "Duplicate demo", number: "000301", bank: "Demo Duplicate Bank",
                  outgoing: true)
        openEditor(app)
        app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].tap()
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
        XCTAssertTrue(row(number: "000301", in: app).waitForExistence(timeout: 5))
        assertRowCount(2, number: "000301", in: app)
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
        let paymentDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Payment date,")).firstMatch
        XCTAssertFalse(paymentDate.exists)
        XCTAssertTrue(app.buttons["primarySettlement"].waitForExistence(timeout: 5))
        capture(app, "Build 6 English payment action next to amount")
        app.buttons["primarySettlement"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "actualSettlementDate").firstMatch.waitForExistence(timeout: 5))
        app.buttons["confirmSettlement"].tap()
        waitForAbsence(app.buttons["confirmSettlement"])
        XCTAssertTrue(paymentDate.waitForExistence(timeout: 5))
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "dd/MM/yyyy"
        XCTAssertEqual(paymentDate.label, "Payment date, " + dateFormatter.string(from: Date()),
                       "The confirmed default actual payment date must be visible, not only a changed status")
        XCTAssertFalse(app.buttons["primarySettlement"].exists)
        capture(app, "Build 6 English actual payment date saved")
        goBack(in: app)
        XCTAssertTrue(app.navigationBars["Cheques"].waitForExistence(timeout: 5))
        let paid = row(number: "000401", in: app)
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        let markedPaid = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Paid"), object: paid)
        XCTAssertEqual(XCTWaiter.wait(for: [markedPaid], timeout: 5), .completed,
                       "A paid outgoing cheque stays in the sheet and reads as paid")
        capture(app, "English paid cheque kept in the outgoing sheet")
    }

    func testSoftDeletionCanBeUndoneAndLaterRestoredFromSettingsTrash() {
        let app = launch()
        addCheque(app, amount: "150.00", party: "Restore demo", number: "000501", outgoing: true)
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
        waitForRowRemoval(cheque, in: app)
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
        app.tabBars.buttons["Settings"].tap()
        if !app.navigationBars["Settings"].exists { goBack(in: app) }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let tools = app.descendants(matching: .any).matching(identifier: "dataTools").firstMatch
        reveal(tools, in: app)
        tools.tap()
        XCTAssertTrue(app.navigationBars["Data and backup"].waitForExistence(timeout: 5))
        capture(app, "Build 6 English data and backup tools with fictional records")
        app.buttons["Create encrypted backup"].tap()
        let password = app.secureTextFields["backupPassword"]
        let confirmation = app.secureTextFields["backupPasswordConfirmation"]
        let saveBackup = app.buttons["saveEncryptedBackup"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.exists)
        assertEnabled(saveBackup, expected: false)
        typeSecure(password, value: "short", in: app)
        typeSecure(confirmation, value: "short", in: app)
        assertEnabled(saveBackup, expected: false) // Matching but fewer than ten characters.
        typeSecure(password, value: String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "DemoPass1234", in: app)
        assertEnabled(saveBackup, expected: false) // Long password but confirmation still differs.
        typeSecure(confirmation, value: String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "DemoPass1234", in: app)
        assertEnabled(saveBackup, expected: true)
        capture(app, "Build 6 English encrypted backup matching password ready with fictional records")
        // The file exporter is deliberately never opened; this test verifies the reversible input flow.
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
        XCTAssertTrue(app.staticTexts["لا توجد شيكات صادرة"].waitForExistence(timeout: 5))
        XCTAssertFalse(row(number: "000601", in: app).exists, "The cheques sheet lists outgoing cheques only")
        app.tabBars.buttons["الرئيسية"].tap()
        let dueToday = app.descendants(matching: .any).matching(identifier: "dashboardScope-today").firstMatch
        XCTAssertTrue(dueToday.waitForExistence(timeout: 5))
        reveal(dueToday, in: app)
        dueToday.tap()
        XCTAssertTrue(row(number: "000601", in: app).waitForExistence(timeout: 5))
        app.buttons["period-today"].tap()
        XCTAssertTrue(row(number: "000601", in: app).exists)
        XCTAssertTrue(app.buttons["clearActiveFilters"].exists)
        app.segmentedControls["listDirectionPicker"].buttons["صادر"].tap()
        waitForRowRemoval(row(number: "000601", in: app), in: app)
        app.buttons["clearActiveFilters"].tap()
        XCTAssertTrue(row(number: "000601", in: app).waitForExistence(timeout: 5))
        capture(app, "Build 6 Arabic outstanding cheques and quick periods")
        app.tabBars.buttons["الإعدادات"].tap()
        let tools = app.descendants(matching: .any).matching(identifier: "dataTools").firstMatch
        reveal(tools, in: app)
        tools.tap()
        XCTAssertTrue(app.navigationBars["البيانات والنسخ الاحتياطي"].waitForExistence(timeout: 5))
        capture(app, "Build 6 Arabic data and backup tools with fictional records")
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
        for (identifier, value) in [("partyField", party), ("chequeNumberField", number)] {
            let next = app.buttons["Next"].exists ? app.buttons["Next"] : app.buttons["التالي"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertTrue(next.isHittable)
            next.tap()
            let field = app.textFields[identifier]
            waitForKeyboardFocus(field, in: app)
            field.typeText(value)
        }
    }

    private func fillField(_ identifier: String, value: String, in app: XCUIApplication) {
        // A focused Form scrolls again as the keyboard moves. Dismiss it before revealing
        // a nonsequential field, then verify the newly selected input really receives focus.
        hideKeyboard(in: app)
        let field = app.textFields[identifier]
        reveal(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        waitForKeyboardFocus(field, in: app)
        field.typeText(value)
    }

    /// A numeric keyboard has no alphabet keys. Paste exercises the real field-validation path
    /// for both Arabic numerals and invalid external input instead of relying on keyboard layout.
    @MainActor
    private func paste(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        hideKeyboard(in: app, arabic: true)
        reveal(field, in: app)
        field.tap()
        waitForKeyboardFocus(field, in: app)
        UIPasteboard.general.string = value
        field.press(forDuration: 1.1)
        let pastePredicate = NSPredicate(format: "label IN %@", ["Paste", "لصق"])
        let pasteButton = app.buttons.matching(pastePredicate).firstMatch
        let pasteMenuItem = app.menuItems.matching(pastePredicate).firstMatch
        let visiblePaste = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pasteButton.exists || pasteMenuItem.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visiblePaste], timeout: 5), .completed,
                       "The standard text-editing menu must expose Paste")
        (pasteButton.exists ? pasteButton : pasteMenuItem).tap()
        let permission = app.alerts.buttons.matching(NSPredicate(
            format: "label IN %@", ["Allow Paste", "السماح باللصق"])).firstMatch
        if permission.waitForExistence(timeout: 1) { permission.tap() }
    }

    private func assertValue(_ expected: String, in field: XCUIElement) {
        let canonical = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [canonical], timeout: 5), .completed,
                       "Numeric fields must display their accepted English-digit value immediately")
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
        let labels = arabic ? ["تم", "Done"] : ["Done", "تم"]
        guard let done = labels.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) else {
            captureDiagnostics(app, "Build 6 keyboard Done control unavailable")
            XCTFail("Expected a visible keyboard Done control before revealing another field")
            return
        }
        done.tap()
        waitForAbsence(app.keyboards.firstMatch)
    }

    private func isBlank(_ field: XCUIElement) -> Bool {
        let value = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        return value.isEmpty || value == placeholder
    }

    private func waitForKeyboardFocus(_ field: XCUIElement, in app: XCUIApplication) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists && field.debugDescription.contains("Keyboard Focused")
        }, object: field)
        let result = XCTWaiter.wait(for: [focused], timeout: 5)
        if result != .completed { captureDiagnostics(app, "Build 6 input did not receive keyboard focus") }
        XCTAssertEqual(result, .completed, "The selected field must receive focus before typing")
    }

    private func typeSecure(_ field: XCUIElement, value: String, in app: XCUIApplication) {
        reveal(field, in: app)
        field.tap()
        waitForKeyboardFocus(field, in: app)
        field.typeText(value)
    }

    private func assertEnabled(_ control: XCUIElement, expected: Bool) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in control.isEnabled == expected }, object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed,
                       "Encrypted backup saving must reflect both the minimum length and confirmation match")
    }

    private func setSwitch(_ element: XCUIElement, enabled: Bool, in app: XCUIApplication) {
        let expected = enabled ? "1" : "0"
        reveal(element, in: app, fullyVisible: true)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        if (element.value as? String) == expected { return }
        captureDiagnostics(app, "Build 6 keep entry details switch \(expected) before tap")
        // iOS 26 exposes the label and switch as one wide accessibility element.
        // Its midpoint lands on the label; the English switch glyph is at the trailing edge.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        captureDiagnostics(app, "Build 6 keep entry details switch \(expected) after tap")
        XCTAssertEqual(result, .completed, "Expected the visible toggle glyph to change the saved preference")
        XCTAssertEqual(element.value as? String, expected)
    }

    /// Counts distinct cheque rows, so an accessibility wrapper sharing a row's identifier is not a second record.
    private func assertRowCount(_ expected: Int, number: String, in app: XCUIApplication) {
        let query = rows(number: number, in: app)
        let matchesCount = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Set(query.allElementsBoundByIndex.map(\.identifier)).count == expected
        }, object: nil)
        let result = XCTWaiter.wait(for: [matchesCount], timeout: 5)
        if result != .completed { captureDiagnostics(app, "Sheet row count did not match \(expected)") }
        XCTAssertEqual(result, .completed, "The outgoing sheet must list \(expected) cheques numbered \(number)")
    }

    private func rows(number: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", number))
    }

    private func row(number: String, in app: XCUIApplication) -> XCUIElement { rows(number: number, in: app).firstMatch }

    private func waitForEditorDismissal(_ app: XCUIApplication) { waitForAbsence(app.buttons["saveCheque"]) }

    private func waitForAbsence(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed { captureDiagnostics(XCUIApplication(), "Build 6 element still present after wait") }
        XCTAssertEqual(result, .completed, "Expected \(element) to disappear")
    }

    /// A row that left the filtered list while its detail screen was pushed can linger in the
    /// accessibility tree as an invisible, non-hittable collection cell until the next layout pass.
    /// The screen is static during this wait, so treat a non-hittable row as removed; the lists in
    /// these flows hold one or two rows, so a merely scrolled-away row cannot satisfy this.
    private func waitForRowRemoval(_ row: XCUIElement, in app: XCUIApplication) {
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !row.exists || !row.isHittable }, object: row)
        let result = XCTWaiter.wait(for: [removed], timeout: 10)
        if result != .completed { captureDiagnostics(app, "Build 6 cheque row still visible after removal") }
        XCTAssertEqual(result, .completed, "Expected the cheque row to leave the visible list")
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, fullyVisible: Bool = false) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        for _ in 0..<12 {
            let frame = window.frame
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = keyboard.exists && keyboard.frame.height > 0
            let predictions = app.otherElements["Typing Predictions"].firstMatch
            let keyboardTop = keyboardVisible ? keyboard.frame.minY : frame.maxY
            let accessoryTop = keyboardVisible ?
                (predictions.exists && predictions.frame.height > 0 ? predictions.frame.minY : keyboardTop - 60) : keyboardTop
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.compactMap { bar -> CGFloat? in
                guard bar.exists else { return nil }
                let barFrame = bar.frame
                guard barFrame.height > 0, barFrame.intersects(frame) else { return nil }
                return barFrame.maxY
            }.max() ?? frame.minY + 100
            let savedNotice = app.staticTexts["consecutiveChequeSaved"]
            let noticeBottom = savedNotice.exists && savedNotice.frame.height > 0 && savedNotice.frame.intersects(frame) ?
                savedNotice.frame.maxY : navigationBottom
            let top = max(frame.minY + 100, max(navigationBottom, noticeBottom) + 8)
            let toolbarTop = app.toolbars.allElementsBoundByIndex.compactMap { toolbar -> CGFloat? in
                guard toolbar.exists else { return nil }
                let toolbarFrame = toolbar.frame
                guard toolbarFrame.height > 0, toolbarFrame.intersects(frame), toolbarFrame.minY > top else { return nil }
                return toolbarFrame.minY
            }.min() ?? frame.maxY
            let tabBar = app.tabBars.firstMatch
            let tabBarTop = tabBar.exists && tabBar.frame.height > 0 && tabBar.frame.intersects(frame) ?
                tabBar.frame.minY : frame.maxY
            // The last detail action can end at 836, just above a tab bar starting at 854.
            // Use actual visible chrome rather than excluding an unreachable 109-point bottom strip.
            let bottom = min(frame.maxY - 34, min(tabBarTop, min(toolbarTop, min(keyboardTop, accessoryTop)))) - 8
            guard bottom > top + 50 else { break }
            let targetExists = element.exists
            let targetFrame = targetExists ? element.frame : CGRect.null
            if targetExists {
                let fullyInside = targetFrame.minY >= top && targetFrame.maxY <= bottom
                let centerInside = targetFrame.midY >= top && targetFrame.midY <= bottom
                let requireFullFrame = fullyVisible || !element.identifier.hasPrefix("cheque-row-")
                if element.isHittable && (requireFullFrame ? fullyInside : centerInside) { return }
            }
            let requireFullFrame = targetExists && (fullyVisible || !element.identifier.hasPrefix("cheque-row-"))
            let targetTop = requireFullFrame ? targetFrame.minY : targetFrame.midY
            let targetBottom = requireFullFrame ? targetFrame.maxY : targetFrame.midY
            let above = targetExists && targetFrame.height > 0 && targetTop < top
            let delta = targetExists && targetFrame.height > 0 ?
                (above ? top - targetTop : targetBottom - bottom) : 100
            // Search a lazy Settings/Form section with a longer slow drag until it materializes.
            // Once its frame exists, approach the exact gap without jumping past the target.
            let distance = targetExists && targetFrame.height > 0 ?
                min(min(140, (bottom - top) * 0.4), max(24, delta * 0.7 + 12)) : (bottom - top) * 0.65
            let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let startY = above ? top + 15 : bottom
            let endY = above ? startY + distance : startY - distance
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: endY - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        captureDiagnostics(app, "Build 6 enhancement field remained offscreen")
        XCTFail("Expected the control to become visible")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureDiagnostics(_ app: XCUIApplication, _ name: String) {
        capture(app, name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
