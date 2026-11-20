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
        func waitForDestination(_ identifier: String) {
            let marker = element(identifier)
            XCTAssertTrue(marker.waitForExistence(timeout: 12), "Missing destination landmark \(identifier)")
            let homeLeft = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: homeBalance)
            XCTAssertEqual(XCTWaiter.wait(for: [homeLeft], timeout: 12), .completed,
                           "The home content must leave the screen before capturing \(identifier)")
            XCTAssertTrue(marker.isHittable, "The destination landmark \(identifier) must be visible")
        }
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 15))
        XCTAssertTrue(homeBalance.waitForExistence(timeout: 10))
        capture("01-home")

        let ledger = nativeTab(.cheques, in: app)
        XCTAssertTrue(ledger.waitForExistence(timeout: 5))
        ledger.tap()
        waitForDestination("shownChequeCount")
        let row = element("cheque-row-00000000-0000-4000-8000-000000004182")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("004182"))
        capture("02-ledger")
        row.tap()
        let edit = app.buttons["editCheque"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        capture("04-detail")
        edit.tap()

        let resources = Bundle(for: type(of: self))
        let translationPath = try XCTUnwrap(resources.path(forResource: locale, ofType: "lproj"))
        let translations = try XCTUnwrap(Bundle(path: translationPath))
        let numberField = app.textFields["chequeNumberField"]
        for _ in 0..<8 where !numberField.isHittable { app.swipeUp() }
        XCTAssertEqual(numberField.value as? String, "004182")
        numberField.tap()
        numberField.typeText("9")
        let edited = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "9"), object: numberField)
        XCTAssertEqual(XCTWaiter.wait(for: [edited], timeout: 8), .completed)
        let done = translations.localizedString(forKey: "Done", value: nil, table: nil)
        let finishTyping = app.toolbars.buttons.matching(NSPredicate(format: "label == %@", done)).firstMatch
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
        if use.exists && use.isHittable {
            XCTAssertTrue(use.isEnabled)
            use.tap()
        } else {
            // UIKit moves a long translated toolbar action into its system overflow menu.
            let overflow = app.navigationBars.buttons.matching(identifier: "OverflowBarButtonItem").firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 8) && overflow.isHittable)
            overflow.tap()
            let title = translations.localizedString(forKey: "Use selected", value: nil, table: nil)
            let actions = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ OR label == %@ OR title == %@", "useOCRFields", title, title))
            guard actions.firstMatch.waitForExistence(timeout: 8),
                  let action = actions.allElementsBoundByIndex.first(where: { $0.isEnabled && $0.isHittable }) else {
                XCTFail("Missing enabled OCR action in overflow for \(locale); expected '\(title)'. " + app.debugDescription)
                return
            }
            action.tap()
        }
        // Verify the action's effect in the editor. Nothing is saved to the cheque.
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: numberChoice)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        let amount = app.textFields["amountField"]
        for _ in 0..<10 where !amount.isHittable { app.swipeDown() }
        XCTAssertEqual(amount.value as? String, "1250.000",
                       "The editor must show the recognized JOD amount.")
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

        // Relaunch to discard the editor draft without saving changes to the source cheque.
        app.terminate()
        app.launch()
        let calendar = nativeTab(.calendar, in: app)
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        waitForDestination("calendarNextMonth")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "The selected date must contain the seeded incoming cheque.")
        capture("05-calendar")
    }
}
