import XCTest
import UIKit

/// Optical recognition runs on the same Vision path used after scanning a cheque on a phone.
final class StoreScreenshotUITests: XCTestCase {
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

        let scan = app.buttons["readChequeImage"]
        for _ in 0..<12 where !scan.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        let numberChoice = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "004182")).firstMatch
        guard numberChoice.waitForExistence(timeout: 90) else {
            XCTFail("Vision did not open the review of the recognized cheque number. " + app.debugDescription)
            return
        }
        XCTAssertEqual(numberChoice.value as? String, "1", "The recognized number must be selected.")
        let use = app.buttons.matching(identifier: "useOCRFields").firstMatch
        if use.exists && use.isHittable {
            XCTAssertTrue(use.isEnabled)
        } else {
            // UIKit moves a long translated toolbar action into its system overflow menu.
            let overflow = app.navigationBars.buttons.matching(identifier: "OverflowBarButtonItem").firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 8) && overflow.isHittable)
            overflow.tap()
            let resources = Bundle(for: type(of: self))
            let path = try XCTUnwrap(resources.path(forResource: locale, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let title = bundle.localizedString(forKey: "Use selected", value: nil, table: nil)
            let action = app.descendants(matching: .any).matching(NSPredicate(
                format: "(elementType == %d OR elementType == %d) AND (identifier == %@ OR label == %@)",
                XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue, "useOCRFields", title
            )).firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 8) && action.isEnabled && action.isHittable,
                          "The overflow must offer the enabled localized Use selected action.")
            // Dismiss using the menu backdrop without applying or changing any recognized value.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: action)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
            XCTAssertTrue(numberChoice.isHittable)
            XCTAssertEqual(numberChoice.value as? String, "1")
        }
        capture("03-review")
        let amountChoice = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "1250.000")).firstMatch
        for _ in 0..<4 where !amountChoice.exists { app.swipeUp() }
        XCTAssertTrue(amountChoice.exists, "The review must contain the fixture amount recognized by Vision.")
        XCTAssertEqual(amountChoice.value as? String, "1")

        // Relaunch to leave the read-only review without accepting changes to the source cheque.
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
