import XCTest

final class ShekatiUITests: XCTestCase {
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
        if !number.isHittable { app.swipeUp() }
        number.tap()
        number.typeText("000182")
        let party = app.textFields["partyField"]
        if !party.isHittable { app.swipeUp() }
        party.tap()
        party.typeText("CI cheque")
        app.buttons["saveCheque"].tap()
        XCTAssertTrue(app.staticTexts["CI cheque"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Cheques"].tap()
        XCTAssertTrue(app.staticTexts["CI cheque"].waitForExistence(timeout: 5))
        let numberLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "000182")).firstMatch
        XCTAssertTrue(numberLabel.exists)
        app.staticTexts["CI cheque"].tap()
        XCTAssertTrue(app.navigationBars["Cheque"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["000182"].exists)
    }

    func testArabicFirstRunAndEnglishLanguageSwitch() {
        let app = launch(arabic: true)
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].exists)
        app.tabBars.buttons["الإعدادات"].tap()
        let language = app.buttons["languagePicker"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance and language"].exists || app.staticTexts["APPEARANCE AND LANGUAGE"].exists)
    }
}
