import StoreKitTest
import XCTest

final class SubscriptionPurchaseScreenTests: XCTestCase {
    func testPaywallShowsBothStoreKitPricesAndRestoration() throws {
        continueAfterFailure = false
        let catalog = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ShekatiPlus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: catalog)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()
        let chooseCurrency = app.buttons["chooseCurrency"]
        XCTAssertTrue(chooseCurrency.waitForExistence(timeout: 12))
        for _ in 0..<4 where !chooseCurrency.isHittable { app.swipeUp() }
        chooseCurrency.tap()
        let dollar = app.buttons["currency_USD"]
        XCTAssertTrue(dollar.waitForExistence(timeout: 8))
        dollar.tap()
        openMoreDestination("moreSubscriptionLink", in: app)
        let monthly = app.buttons["com.mf103871.shekati.plus.monthly"]
        let annual = app.buttons["com.mf103871.shekati.plus.annual"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 25))
        XCTAssertTrue(annual.exists)
        XCTAssertTrue(monthly.label.contains("4.99"), monthly.label)
        XCTAssertTrue(annual.label.contains("39.99"), annual.label)
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
        attachNativeScreenshot(in: app, name: "Shekati-Plus-US-review")
    }
}

