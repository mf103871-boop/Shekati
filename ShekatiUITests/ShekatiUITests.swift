import XCTest

final class ShekatiUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (arabic ? ["--arabic"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["chooseCurrency"].waitForExistence(timeout: 10))
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
        amount.tap()
        amount.typeText("125.50")
        let number = app.textFields["chequeNumberField"]
        reveal(number, in: app)
        number.tap()
        number.typeText("000182")
        let party = app.textFields["partyField"]
        reveal(party, in: app)
        party.tap()
        party.typeText("CI cheque")
        app.buttons["saveCheque"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.buttons["saveCheque"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        app.tabBars.buttons["Cheques"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "cheque-row-", "CI cheque", "000182"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("CI cheque"))
        XCTAssertTrue(row.label.contains("000182"))
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["000182"].exists)
    }

    func testArabicFirstRunAndEnglishLanguageSwitch() {
        let app = launch(arabic: true)
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].exists)
        app.tabBars.buttons["الإعدادات"].tap()
        let language = app.descendants(matching: .any).matching(identifier: "languagePicker").firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance and language"].exists || app.staticTexts["APPEARANCE AND LANGUAGE"].exists)
    }

    /// Drag only through the visible form/list area, keeping the gesture above any software keyboard.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.isHittable { return }
        let candidates = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
        guard let scroller = candidates.first(where: { $0.isHittable }) else {
            XCTFail("Expected a visible form or list scroll container")
            return
        }
        for _ in 0..<5 {
            if element.isHittable { return }
            let frame = scroller.frame
            let keyboard = app.keyboards.firstMatch
            let visibleBottom = min(frame.maxY, keyboard.exists ? keyboard.frame.minY : frame.maxY) - 24
            let visibleTop = frame.minY + 60
            guard visibleBottom > visibleTop + 40 else {
                XCTFail("The visible scroll area is too small to reveal the field")
                return
            }
            let origin = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: visibleBottom - frame.minY))
            let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: visibleTop - frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "Expected the field or cheque row to become visible after scrolling")
    }
}
