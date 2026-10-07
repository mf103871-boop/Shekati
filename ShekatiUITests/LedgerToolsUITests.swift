import XCTest

/// Exercises real entry and navigation against isolated in-memory data; no stored user cheques are used.
final class LedgerToolsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSelectionTotalsPaidHistoryAndCreatingChequeOnFreeDueDate() {
        let app = launch()
        addOutgoingCheque(app, amount: "25.50", party: "Ledger A", number: "000901")
        addOutgoingCheque(app, amount: "74.50", party: "Ledger B", number: "000902")
        app.tabBars.buttons["Cheques"].tap()
        let firstCheque = row(number: "000901", in: app)
        let secondCheque = row(number: "000902", in: app)
        XCTAssertTrue(firstCheque.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCheque.exists)

        app.buttons["selectChequesButton"].tap()
        firstCheque.tap()
        secondCheque.tap()
        assertSelection(count: "2", amount: "100.00", in: app)
        capture(app, "Two selected outgoing cheques total exactly 100.00")
        firstCheque.tap()
        assertSelection(count: "1", amount: "74.50", in: app)
        app.buttons["selectChequesButton"].tap()

        // Paying is a dated action. The original record leaves the primary scope and remains in history.
        firstCheque.tap()
        XCTAssertTrue(app.buttons["primarySettlement"].waitForExistence(timeout: 5))
        app.buttons["primarySettlement"].tap()
        XCTAssertTrue(element("actualSettlementDate", in: app).waitForExistence(timeout: 5))
        app.buttons["confirmSettlement"].tap()
        waitForAbsence(app.buttons["confirmSettlement"])
        let paymentDate = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Payment date,")).firstMatch
        XCTAssertTrue(paymentDate.waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(app.navigationBars["Cheques"].waitForExistence(timeout: 5))
        waitForRowRemoval(firstCheque)
        XCTAssertTrue(secondCheque.exists && secondCheque.isHittable)

        let scopes = app.segmentedControls["outgoingPaymentScopePicker"]
        XCTAssertTrue(scopes.waitForExistence(timeout: 5))
        scopes.buttons["Paid cheques"].tap()
        XCTAssertTrue(firstCheque.waitForExistence(timeout: 5))
        XCTAssertTrue(firstCheque.label.contains("Paid"))
        waitForRowRemoval(secondCheque)
        app.buttons["selectChequesButton"].tap()
        app.buttons["selectAllChequesButton"].tap()
        assertSelection(count: "1", amount: "25.50", in: app)
        capture(app, "Paid cheques have their own history and selection total")
        app.buttons["clearSelectedChequesButton"].tap()
        assertSelection(count: "0", amount: "0.00", in: app)
        app.buttons["selectChequesButton"].tap()
        scopes.buttons["Cheques"].tap()

        // The remaining unpaid cheque occupies today. A free date opens a real outgoing draft.
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayID = "freeDay-" + dateText(today, format: "yyyy-MM-dd")
        let tomorrowID = "freeDay-" + dateText(tomorrow, format: "yyyy-MM-dd")
        app.buttons["freeChequeDaysButton"].tap()
        XCTAssertTrue(app.buttons["closeFreeDays"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("freeDaysFromDate", in: app).exists)
        XCTAssertTrue(element("freeDaysThroughDate", in: app).exists)
        XCTAssertFalse(app.buttons[todayID].exists, "Today already has an unpaid outgoing cheque")
        let freeTomorrow = app.buttons[tomorrowID]
        XCTAssertTrue(freeTomorrow.waitForExistence(timeout: 5))
        capture(app, "Free due dates exclude days already occupied by unpaid outgoing cheques")
        freeTomorrow.tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].isSelected)
        let plannedDate = app.staticTexts["plannedDueDateSummary"]
        XCTAssertTrue(plannedDate.exists)
        XCTAssertTrue(plannedDate.label.contains(dateText(tomorrow, format: "dd/MM/yyyy")),
                      "Choosing an available day must prefill that exact due date")
        XCTAssertFalse(plannedDate.label.unicodeScalars.contains {
            (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value)
        })
        capture(app, "Chosen free date prefills the outgoing cheque with English digits")
        fill(app, amount: "25.00", party: "Available date demo", number: "000903")
        hideKeyboard(in: app)
        app.buttons["saveAndAddAnother"].tap()
        XCTAssertTrue(app.staticTexts["consecutiveChequeSaved"].waitForExistence(timeout: 8))
        hideKeyboard(in: app)
        XCTAssertTrue(app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].isSelected,
                      "Consecutive entry from an outgoing planning route must remain outgoing")
        for identifier in ["amountField", "chequeNumberField"] {
            let field = app.textFields[identifier]
            let value = (field.value as? String) ?? ""
            XCTAssertTrue(value.isEmpty || value == field.placeholderValue,
                          "The next draft must clear the saved cheque's amount and number")
        }
        capture(app, "Consecutive entry from a free date keeps the outgoing type")
        app.buttons["Cancel"].tap()
        waitForAbsence(app.buttons["saveCheque"])
        XCTAssertTrue(app.buttons["closeFreeDays"].waitForExistence(timeout: 5))
        waitForAbsence(freeTomorrow)
        XCTAssertFalse(app.buttons[todayID].exists)
        capture(app, "Saving a cheque removes its due date from the available days")
        app.buttons["closeFreeDays"].tap()
        let scheduledCheque = row(number: "000903", in: app)
        XCTAssertTrue(scheduledCheque.waitForExistence(timeout: 5))
        XCTAssertTrue(scheduledCheque.label.contains(dateText(tomorrow, format: "dd/MM/yyyy")))
        XCTAssertTrue(secondCheque.exists)
        waitForRowRemoval(firstCheque)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseCurrency"].waitForExistence(timeout: 10))
        reveal(app.buttons["chooseCurrency"], in: app)
        app.buttons["chooseCurrency"].tap()
        XCTAssertTrue(app.buttons["currency_USD"].waitForExistence(timeout: 5))
        app.buttons["currency_USD"].tap()
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 5))
        return app
    }

    private func addOutgoingCheque(_ app: XCUIApplication, amount: String, party: String, number: String) {
        app.buttons["addCheque"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        app.segmentedControls["chequeDirectionPicker"].buttons["Outgoing"].tap()
        fill(app, amount: amount, party: party, number: number)
        hideKeyboard(in: app)
        app.buttons["saveCheque"].tap()
        waitForAbsence(app.buttons["saveCheque"])
    }

    private func fill(_ app: XCUIApplication, amount: String, party: String, number: String) {
        let amountField = app.textFields["amountField"]
        reveal(amountField, in: app)
        amountField.tap()
        typeAndAssert(amount, into: amountField, in: app)
        for (identifier, value) in [("partyField", party), ("chequeNumberField", number)] {
            let next = app.buttons["Next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isHittable)
            next.tap()
            // Do not tap the target again: Next must actually hand it the keyboard.
            typeAndAssert(value, into: app.textFields[identifier], in: app)
        }
    }

    private func typeAndAssert(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists && field.isEnabled && app.keyboards.firstMatch.exists
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        field.typeText(text)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 5), .completed,
                       "Text must be delivered to the intended empty field exactly")
    }

    private func hideKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons["Done"].allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(done, "The keyboard must offer Done")
        done?.tap()
        waitForAbsence(app.keyboards.firstMatch)
    }

    private func assertSelection(count: String, amount: String, in app: XCUIApplication) {
        let countElement = element("selectedChequeCount", in: app)
        let amountElement = element("selectedChequeAmount", in: app)
        XCTAssertTrue(countElement.waitForExistence(timeout: 5))
        let exactCount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", count), object: countElement)
        let exactAmount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", amount), object: amountElement)
        XCTAssertEqual(XCTWaiter.wait(for: [exactCount, exactAmount], timeout: 5), .completed,
                       "The footer must recompute the selected count and currency-precise sum")
    }

    private func row(number: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", number)).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dateText(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func waitForAbsence(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    private func waitForRowRemoval(_ row: XCUIElement) {
        // These scopes contain at most two rows, so a non-hittable retained navigation cell
        // cannot be an offscreen valid record. SwiftUI may retain that cell briefly after a pop.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !row.exists || !row.isHittable }, object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "The cheque must leave this scope while remaining available in its proper scope")
    }

    private func goBack(in app: XCUIApplication) {
        let back = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        XCTAssertNotNil(back)
        back?.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            let frame = window.frame
            let top = (app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? frame.minY + 100) + 8
            let keyboard = app.keyboards.firstMatch
            let keyboardTop = keyboard.exists ? keyboard.frame.minY - 60 : frame.maxY
            let tabBar = app.tabBars.firstMatch
            let bottom = min(frame.maxY - 34, min(keyboardTop, tabBar.exists ? tabBar.frame.minY : frame.maxY)) - 8
            let target = element.exists ? element.frame : CGRect.null
            if element.exists && element.isHittable && target.minY >= top && target.maxY <= bottom { return }
            guard bottom > top + 50 else { break }
            let above = element.exists && target.height > 0 && target.minY < top
            let delta = element.exists && target.height > 0 ? (above ? top - target.minY : target.maxY - bottom) : 100
            let distance = min(140, max(24, delta * 0.7 + 12))
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let startY = above ? top + 15 : bottom
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: startY + (above ? distance : -distance) - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        capture(app, "Ledger input did not become visible")
        XCTFail("Expected the requested field to become visible")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
