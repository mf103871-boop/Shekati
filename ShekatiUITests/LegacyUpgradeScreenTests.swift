import XCTest
import UIKit

final class LegacyUpgradeScreenTests: XCTestCase {
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testReopenedLegacyChequeAndBothImages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US", "-language", "en"]
        app.launch()
        let tab = app.tabBars.buttons.matching(NSPredicate(format:"label IN %@", ["Cheques","Checks"])).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout:20),app.debugDescription)
        tab.tap()
        #if LEGACY_BUILD9
        // In the shipped legacy app this tab only lists outgoing cheques.
        // Assert that scope, then reach the actual all-cheques register from Home.
        let outgoing = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", "007309")).firstMatch
        XCTAssertTrue(outgoing.waitForExistence(timeout:12),app.debugDescription)
        capture("Legacy-outgoing")
        app.tabBars.buttons["Home"].tap()
        let all = app.buttons["See all"]
        for _ in 0..<7 where !all.isHittable { app.swipeUp() }
        XCTAssertTrue(all.isHittable,app.debugDescription)
        all.tap()
        #endif
        let row = app.descendants(matching: .any).matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", "004182")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:15),app.debugDescription)
        XCTAssertTrue(row.label.contains("1,250.075") || row.label.contains("1250.075"),row.label)
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable,row.debugDescription)
        capture("Legacy-register")
        row.tap()
        let front = app.buttons.matching(NSPredicate(format:"label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Front","image")).firstMatch
        let back = app.buttons.matching(NSPredicate(format:"label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Back","image")).firstMatch
        XCTAssertTrue(front.waitForExistence(timeout:12),app.debugDescription)
        XCTAssertTrue(back.exists,app.debugDescription)
        capture("Legacy-cheque")
        for _ in 0..<6 where !front.isHittable { app.swipeUp() }
        XCTAssertTrue(front.isHittable)
        front.tap()
        let full = app.images.matching(NSPredicate(format:"label BEGINSWITH[c] %@", "Front")).firstMatch
        if !full.exists {
            let close = app.buttons.matching(NSPredicate(format:"label IN %@", ["Close","Done"])).firstMatch
            XCTAssertTrue(close.waitForExistence(timeout:12) || app.navigationBars["Front"].exists,app.debugDescription)
        }
        capture("Legacy-front")
        app.terminate()
    }
}
