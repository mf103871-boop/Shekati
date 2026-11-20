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
        func tap(_ element: XCUIElement) {
            for _ in 0..<6 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable, element.debugDescription)
            element.tap()
        }
        func fillReason(_ note: String) {
            let reason = app.textFields["Reason"]
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            reason.tap()
            reason.typeText(note + "\n")
            tap(app.buttons["reviewOperation"])
        }
        tap(app.buttons["reviewUnlinkedCheques"])
        let row = app.descendants(matching: .any).matching(identifier: "cheque-row-00000000-0000-4000-8000-000000004182").firstMatch
        tap(row)
        let historical = app.buttons["operation-historicalSettlement"]
        XCTAssertTrue(historical.waitForExistence(timeout: 5))
        let actionTitle = historical.label
        tap(historical)
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
        tap(app.buttons["commitOperation"])
        let history = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", reason, "125.001")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 6))
        XCTAssertTrue(history.label.contains(localizedDueDate(Date())))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<5 where !recorded.isHittable { app.swipeDown() }
        XCTAssertTrue(recorded.waitForExistence(timeout: 5))
        nativeTab(.cheques, in: app).tap()
        tap(row)
        tap(app.buttons["moreChequeActions"])
        tap(app.buttons["Correct last action"])
        let correction = "Incorrect receipt"
        fillReason(correction)
        tap(app.buttons["commitOperation"])
        XCTAssertTrue(historical.waitForExistence(timeout: 6))
        XCTAssertTrue(history.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", correction)).firstMatch.exists)
        nativeTab(.home, in: app).tap()
        XCTAssertTrue(recorded.waitForExistence(timeout: 5))
    }
}
