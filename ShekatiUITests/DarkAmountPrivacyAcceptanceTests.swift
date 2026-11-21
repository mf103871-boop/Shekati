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
        if screen == "detail" { try checkDepositContrast(image, in: app, name: name) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = locale == "ar" && supported.contains("ar-SA") ? ["ar-SA","en-US"] : ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let ocr = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        addText(ocr, name: name + "-OCR")
        let expected = screen == "home" ? [5250, 8450, 3200, 4750, 650] : [1250]
        if phase == "hidden" {
            for value in [8450, 3200, 1250, 1800, 1400, 3500, 10650, 5250, 6500, 4750, 650] {
                XCTAssertFalse(hasAmount(value, in: ax), "\(name) accessory labels contain \(value)")
                XCTAssertFalse(hasAmount(value, in: ocr), "\(name) screenshot OCR contains \(value)")
            }
        } else {
            for value in expected {
                XCTAssertTrue(hasAmount(value, in: ax, withFraction: true), "\(name) needs the full accessible \(value).000 amount.")
                XCTAssertTrue(hasAmount(value, in: ocr, withFraction: true), "\(name) needs the full visible \(value).000 amount.")
            }
        }
    }

    private func hasAmount(_ amount: Int, in text: String, withFraction: Bool = false) -> Bool {
        let digits = String(amount)
        let left = String(digits.dropLast(3))
        let right = String(digits.suffix(3))
        let normalized = text.map { c in c.wholeNumberValue.map(String.init) ?? String(c) }.joined()
        let grouped = left.isEmpty ? right : left + "[,.，٬٫\\h]?" + right
        let minor = withFraction ? "[.,٫]000" : ""
        let pattern = "(?<![0-9])" + grouped + minor + "(?![0-9])"
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    /// Samples the flat interior of the real action button using its accessibility bounds.
    /// The most frequent interior color is its fill. The next substantial non-edge color
    /// belongs to the drawn label/icon, without assuming light or dark foreground.
    private func checkDepositContrast(_ image: CGImage, in app: XCUIApplication, name: String) throws {
        let button = app.buttons["operation-deposit"]
        XCTAssertTrue(button.exists && button.isEnabled && button.isHittable, name)
        let window = app.windows.firstMatch.frame
        let buttonFrame = button.frame
        let area = buttonFrame.insetBy(dx: buttonFrame.width * 0.19, dy: buttonFrame.height * 0.24)
        let sx = CGFloat(image.width) / window.width
        let sy = CGFloat(image.height) / window.height
        let pixels = CGRect(x: (area.minX - window.minX) * sx, y: (area.minY - window.minY) * sy,
                            width: area.width * sx, height: area.height * sy).integral
        let crop = try XCTUnwrap(image.cropping(to: pixels), "\(name): missing action pixels")
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: crop.width, height: crop.height,
                                              bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                              space: space, bitmapInfo: info))
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
        let buffer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let count = crop.width * crop.height
        var frequencies = [Int: Int]()
        for i in 0..<count {
            let p = i * 4
            let rgb = (Int(buffer[p]) << 16) | (Int(buffer[p + 1]) << 8) | Int(buffer[p + 2])
            frequencies[rgb, default: 0] += 1
        }
        let fill = try XCTUnwrap(frequencies.max(by: { $0.value < $1.value }))
        func channels(_ rgb: Int) -> [Int] { [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255] }
        let background = channels(fill.key)
        let foreground = frequencies.filter { sample in
            let differences = zip(channels(sample.key), background).map { abs($0.0 - $0.1) }
            return (differences.max() ?? 0) > 16 && sample.value >= max(30, count / 2000)
        }.max(by: { $0.value < $1.value })
        guard let ink = foreground else {
            addText("Could not distinguish the action label from its background. Crop \(pixels)", name: name + "-contrast")
            XCTFail("\(name): no distinguishable action label")
            return
        }
        func luminance(_ rgb: Int) -> Double {
            let linear = channels(rgb).map { c -> Double in
                let s = Double(c) / 255
                return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let a = luminance(fill.key)
        let b = luminance(ink.key)
        let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        let result = String(format: "Fill #%06X (%d pixels), text #%06X (%d pixels), contrast %.4f:1",
                            fill.key, fill.value, ink.key, ink.value, ratio)
        addText("\(result)\nNative screen crop \(pixels). Button \(buttonFrame).", name: name + "-contrast")
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name): \(result)")
    }

    private func addText(_ value: String, name: String) {
        let attachment = XCTAttachment(string: value)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
