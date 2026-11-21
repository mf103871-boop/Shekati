import StoreKitTest
import XCTest

final class HistoricalSettlementUITests: XCTestCase {
    func testFreeOwnerReviewsUnlinkedSettlementAndCorrectsItWithoutChangingDollars() throws {
        continueAfterFailure = false
        let catalog = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ShekatiPlus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: catalog)
        session.clearTransactions()
        defer { session.clearTransactions() }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--legacy-settlement-test", "-ShekatiStoreLocale", "en-US", "-AppleLocale", "en_US", "-shekati.hideAmounts", "NO"]
        app.launch()
        let recorded = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Recorded balance", "845.01")).firstMatch
        XCTAssertTrue(recorded.waitForExistence(timeout: 12))
        let dollarBalance = recorded.label
        func tapInPage(_ element: XCUIElement) {
            for _ in 0..<6 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable, element.debugDescription)
            element.tap()
        }
        // A swipe outside a confirmation dialog or a menu dismisses it on iOS.
        func tapPresentedButton(_ button: XCUIElement) {
            XCTAssertTrue(button.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(button.isEnabled)
            button.tap()
        }
        func detailAmount(_ title: String, _ value: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", title + ",", value, "JOD"
            )).firstMatch
        }
        func fillReason(_ note: String) {
            let reason = app.textFields["Reason"]
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            reason.tap()
            reason.typeText(note + "\n")
            tapInPage(app.buttons["reviewOperation"])
        }
        tapInPage(app.buttons["reviewUnlinkedCheques"])
        let row = app.descendants(matching: .any).matching(identifier: "cheque-row-00000000-0000-4000-8000-000000004182").firstMatch
        tapInPage(row)
        let historical = app.buttons["operation-historicalSettlement"]
        XCTAssertTrue(historical.waitForExistence(timeout: 5))
        XCTAssertTrue(detailAmount("Remaining amount", "125.001").exists)
        attachNativeScreenshot(in: app, name: "historical-settlement-01-before")
        let actionTitle = historical.label
        tapInPage(historical)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "operationDate").firstMatch.waitForExistence(timeout: 5))
        let review = app.buttons["reviewOperation"]
        XCTAssertFalse(review.isEnabled)
        let reason = "Receipt confirmed"
        fillReason(reason)
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
                                                            actionTitle, "004182", reason)).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("125.001"))
        XCTAssertTrue(summary.label.contains("JOD"))
        XCTAssertTrue(summary.label.contains(localizedDueDate(Date())))
        let confirm = app.buttons.matching(identifier: "commitOperation").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        attachNativeScreenshot(in: app, name: "historical-settlement-02-confirm")
        tapPresentedButton(confirm)
        let history = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", reason, "125.001")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 6))
        XCTAssertTrue(history.label.contains(localizedDueDate(Date())))
        XCTAssertTrue(detailAmount("Remaining amount", "0.000").exists)
        XCTAssertTrue(detailAmount("Amount paid", "125.001").exists)
        attachNativeScreenshot(in: app, name: "historical-settlement-03-applied")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<5 where !recorded.isHittable { app.swipeDown() }
        XCTAssertTrue(recorded.waitForExistence(timeout: 5))
        XCTAssertEqual(recorded.label, dollarBalance)
        nativeTab(.cheques, in: app).tap()
        let allHistory = app.segmentedControls.buttons["All and history"]
        XCTAssertTrue(allHistory.waitForExistence(timeout: 8))
        allHistory.tap()
        tapInPage(row)
        tapInPage(app.buttons["moreChequeActions"])
        tapPresentedButton(app.buttons.matching(identifier: "Correct last action").firstMatch)
        let correction = "Incorrect receipt"
        fillReason(correction)
        let correctionSummary = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "004182", correction
        )).firstMatch
        XCTAssertTrue(correctionSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(correctionSummary.label.contains("Correct last action"))
        tapPresentedButton(confirm)
        XCTAssertTrue(historical.waitForExistence(timeout: 6))
        XCTAssertTrue(detailAmount("Remaining amount", "125.001").exists)
        XCTAssertTrue(history.exists)
        XCTAssertTrue(app.staticTexts["Previous entry excluded"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", correction)).firstMatch.exists)
        attachNativeScreenshot(in: app, name: "historical-settlement-04-corrected")
        nativeTab(.home, in: app).tap()
        XCTAssertTrue(recorded.waitForExistence(timeout: 5))
        XCTAssertEqual(recorded.label, dollarBalance)
    }
}
