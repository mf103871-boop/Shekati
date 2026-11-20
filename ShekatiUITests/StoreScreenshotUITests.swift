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
        app.tabBars.buttons["Cheques"].tap()
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
        app.tabBars.buttons["Home"].tap()
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
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 15))
        XCTAssertTrue(element("outgoingDueAmount").waitForExistence(timeout: 10))
        capture("01-home")

        let ledger = app.tabBars.buttons["tabCheques"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 5))
        ledger.tap()
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
        let use = app.buttons["useOCRFields"]
        guard use.waitForExistence(timeout: 90) else {
            XCTFail("Vision did not open the review of the test cheque. " + app.debugDescription)
            return
        }
        XCTAssertTrue(use.isEnabled, "The synthetic cheque must produce selectable fields through Vision.")
        capture("03-review")

        // Relaunch to leave the read-only review without accepting changes to the source cheque.
        app.terminate()
        app.launch()
        let calendar = app.tabBars.buttons["tabCalendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8), "The selected date must contain the seeded incoming cheque.")
        capture("05-calendar")
    }
}
