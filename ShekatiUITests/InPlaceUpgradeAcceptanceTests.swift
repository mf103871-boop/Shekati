import XCTest

final class InPlaceUpgradeAcceptanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(withDescription: "Simulator notification permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US", "-language", "en-US"]
        app.launch()
        return app
    }

    private func tapInForm(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, element.debugDescription)
        element.tap()
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) {
        let missing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [missing], timeout: timeout), .completed)
    }

    private func addPhoto(at position: Int, in app: XCUIApplication) {
        let photoButton = app.buttons.matching(identifier: "Photos").element(boundBy: position)
        tapInForm(photoButton, in: app)
        let assetLabels = NSPredicate(format: "label BEGINSWITH[c] 'Photo,' OR label BEGINSWITH[c] 'Photo '")
        let assets = app.descendants(matching: .any).matching(assetLabels)
        let grid = app.collectionViews.cells
        let presented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in assets.firstMatch.exists || grid.firstMatch.exists }, object: nil)
        _ = XCTWaiter.wait(for: [presented], timeout: 12)
        var photoFrames: [CGRect] = []
        let thumbnails = assets.allElementsBoundByIndex.filter { element in
            let frame = element.frame
            guard element.isHittable, [.image, .cell, .button].contains(element.elementType), frame.width > 30, frame.height > 30, !photoFrames.contains(where: { abs($0.midX - frame.midX) < 5 && abs($0.midY - frame.midY) < 5 }) else { return false }
            photoFrames.append(frame)
            return true
        }
        if thumbnails.count > position {
            thumbnails[position].tap()
        } else {
            let cells = grid.allElementsBoundByIndex.filter { cell in
                let frame = cell.frame
                return cell.isHittable && frame.width > 45 && frame.height > 45 && frame.width < app.windows.firstMatch.frame.width * 0.65
            }
            XCTAssertGreaterThan(cells.count, position, app.debugDescription)
            cells[position].tap()
        }
        let attached = app.buttons.matching(identifier: "Remove image").element(boundBy: position)
        XCTAssertTrue(attached.waitForExistence(timeout: 15), app.debugDescription)
    }

    private func findHistoryCheque(in app: XCUIApplication) {
        nativeTab(.cheques, in: app).tap()
        let all = app.segmentedControls.buttons["All and history"]
        XCTAssertTrue(all.waitForExistence(timeout: 12))
        all.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "cheque-row-", "000417")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), app.debugDescription)
        row.tap()
    }

    private func verifyReopenedData(in app: XCUIApplication, build: String) {
        let balance = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Recorded balance,", "125.50")).firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bank account,")).firstMatch.exists)
        attachNativeScreenshot(in: app, name: "Upgrade-" + build + "-account")
        findHistoryCheque(in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Upgrade Studio")).firstMatch.exists)
        let front = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Front", "image")).firstMatch
        let back = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Back", "image")).firstMatch
        XCTAssertTrue(front.waitForExistence(timeout: 10))
        XCTAssertTrue(back.exists)
        attachNativeScreenshot(in: app, name: "Upgrade-" + build + "-cheque")
    }

    func testPrepareAndReopenBuild16() {
        let app = launch()
        let choose = app.buttons["chooseCurrency"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15), "Build 16 must start on an empty simulator")
        tapInForm(choose, in: app)
        app.buttons["currency_USD"].tap()
        let add = app.buttons["addCheque"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let amount = app.textFields["amountField"]
        tapInForm(amount, in: app)
        amount.typeText("125.50")
        for (field, text) in [("partyField", "Upgrade Studio"), ("chequeNumberField", "000417")] {
            let next = app.buttons["Next"]
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
            app.textFields[field].typeText(text)
        }
        let done = app.buttons.matching(identifier: "Done").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(done)
        done?.tap()
        waitForAbsence(app.keyboards.firstMatch, timeout: 25)
        let photos = app.descendants(matching: .any).matching(identifier: "chequeImageOptions").firstMatch
        tapInForm(photos, in: app)
        addPhoto(at: 0, in: app)
        addPhoto(at: 1, in: app)
        app.buttons["saveCheque"].tap()
        waitForAbsence(app.buttons["saveCheque"], timeout: 20)
        findHistoryCheque(in: app)
        tapInForm(app.buttons["operation-deposit"], in: app)
        tapInForm(app.buttons["reviewOperation"], in: app)
        let confirm = app.buttons.matching(identifier: "commitOperation").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        recordBankSettlement(in: app)
        nativeTab(.home, in: app).tap()
        let recorded = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Recorded balance,", "125.50")).firstMatch
        XCTAssertTrue(recorded.waitForExistence(timeout: 20))
        app.terminate()
        app.launch()
        verifyReopenedData(in: app, build: "16")
        app.terminate()
    }

    func testReopenAndInspectBuild17() {
        let app = launch()
        XCTAssertFalse(app.buttons["chooseCurrency"].exists)
        verifyReopenedData(in: app, build: "17")
        app.terminate()
    }
}
