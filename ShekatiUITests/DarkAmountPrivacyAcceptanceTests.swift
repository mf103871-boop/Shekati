import XCTest
import Vision
import UIKit

final class DarkAmountPrivacyAcceptanceTests: XCTestCase {
    func testEnglishDarkAmounts() throws { try exercise("en-US") }
    func testArabicDarkAmounts() throws { try exercise("ar") }

    private func exercise(_ locale: String) throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--ui-testing", "--store-screens", "-ShekatiStoreLocale", locale,
                               "-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        app.launch()

        let hide = locale == "ar" ? "إخفاء المبالغ" : "Hide amounts"
        let show = locale == "ar" ? "إظهار المبالغ" : "Show amounts"
        XCTAssertTrue(app.buttons["addCheque"].waitForExistence(timeout: 20))
        if app.buttons[show].exists { app.buttons[show].tap() }
        try inspect("home", phase: "visible", locale: locale, app: app)
        try detail(locale, in: app)
        try inspect("detail", phase: "visible", locale: locale, app: app)

        for (phase, button, opposite) in [("hidden", hide, show), ("restored", show, hide)] {
            nativeTab(.home, in: app).tap()
            XCTAssertTrue(app.buttons[button].waitForExistence(timeout: 10))
            app.buttons[button].tap()
            XCTAssertTrue(app.buttons[opposite].waitForExistence(timeout: 10))
            try inspect("home", phase: phase, locale: locale, app: app)
            try detail(locale, in: app)
            try inspect("detail", phase: phase, locale: locale, app: app)
        }
    }

    private func detail(_ locale: String, in app: XCUIApplication) throws {
        nativeTab(.cheques, in: app).tap()
        let edit = app.buttons["editCheque"]
        if !edit.exists {
            let row = app.descendants(matching: .any)
                .matching(identifier: "cheque-row-00000000-0000-4000-8000-000000004182").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 12))
            row.tap()
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 12))
    }

    private func inspect(_ screen: String, phase: String, locale: String, app: XCUIApplication) throws {
        let name = "\(locale)-\(screen)-\(phase)"
        let snapshot = try app.snapshot()
        var labels: [String] = []
        func collect(_ node: XCUIElementSnapshot) {
            labels.append(node.label)
            if let value = node.value { labels.append(String(describing: value)) }
            if let placeholder = node.placeholderValue { labels.append(placeholder) }
            node.children.forEach(collect)
        }
        collect(snapshot)
        let ax = labels.filter { !$0.isEmpty }.joined(separator: "\n")
        addText(ax, name: name + "-AX-labels")
        addText(app.debugDescription, name: name + "-AX-tree")
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name + "-screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        let image = try XCTUnwrap(shot.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = locale == "ar" && supported.contains("ar-SA") ? ["ar-SA","en-US"] : ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let ocr = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        addText(ocr, name: name + "-OCR")
        let expected = screen == "home" ? [8450, 3200] : [1250]
        if phase == "hidden" {
            for value in [8450, 3200, 1250, 1800, 1400, 3500, 10650, 5250, 6500] {
                XCTAssertFalse(hasAmount(value, in: ax), "\(name) accessory labels contain \(value)")
                XCTAssertFalse(hasAmount(value, in: ocr), "\(name) screenshot OCR contains \(value)")
            }
        } else {
            for value in expected {
                XCTAssertTrue(hasAmount(value, in: ax), "\(name) needs a positive accessibility control for \(value)")
            }
        }
    }

    private func hasAmount(_ amount: Int, in text: String) -> Bool {
        let digits = String(amount)
        let left = String(digits.dropLast(3))
        let right = String(digits.suffix(3))
        let normalized = text.map { c in c.wholeNumberValue.map(String.init) ?? String(c) }.joined()
        let pattern = "(?<![0-9])" + left + "[,.，٬٫\\h]?" + right + "(?![0-9])"
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    private func addText(_ value: String, name: String) {
        let attachment = XCTAttachment(string: value)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
