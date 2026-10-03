import Foundation
import XCTest
@testable import ShekatiCore

final class CurrencyMathTests: XCTestCase {
    func testZeroTwoThreeAndFourDecimalCurrencies() {
        XCTAssertEqual(CurrencyMath.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(CurrencyMath.fractionDigits(for: "usd"), 2)
        XCTAssertEqual(CurrencyMath.fractionDigits(for: "JOD"), 3)
        XCTAssertEqual(CurrencyMath.fractionDigits(for: "CLF"), 4)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("120", currencyCode: "JPY"), 120)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("120.35", currencyCode: "USD"), 12035)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("120.351", currencyCode: "JOD"), 120351)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("0.0001", currencyCode: "CLF"), 1)
    }

    func testArabicPersianAndCommaDecimals() {
        XCTAssertEqual(CurrencyMath.parseMinorUnits(" ١٢٣٫٤٥٦ ", currencyCode: "JOD"), 123456)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("۱۲۳.۴۵", currencyCode: "USD"), 12345)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("12,50", currencyCode: "USD"), 1250)
        XCTAssertEqual(CurrencyMath.parseMinorUnits("00012.5", currencyCode: "USD"), 1250)
    }

    func testRejectsInvalidAndOverpreciseValues() {
        for text in ["", " ", "0", "0.00", "-1", "+1", ".25", "1.", "1.234", "1,234.50", "١٬٢٣٤٫٥٠", "1 234", "1e3", "NaN", "USD 1", "1/2"] {
            XCTAssertNil(CurrencyMath.parseMinorUnits(text, currencyCode: "USD"), text)
        }
        XCTAssertNil(CurrencyMath.parseMinorUnits("12.0", currencyCode: "JPY"))
        XCTAssertNil(CurrencyMath.parseMinorUnits("12.3456", currencyCode: "JOD"))
    }

    func testExactInt64BoundaryAndOverflow() {
        XCTAssertEqual(CurrencyMath.parseMinorUnits("92233720368547758.07", currencyCode: "USD"), Int64.max)
        XCTAssertNil(CurrencyMath.parseMinorUnits("92233720368547758.08", currencyCode: "USD"))
        XCTAssertEqual(CurrencyMath.parseMinorUnits("9223372036854775.807", currencyCode: "JOD"), Int64.max)
        XCTAssertNil(CurrencyMath.parseMinorUnits("999999999999999999999999", currencyCode: "JPY"))
    }

    func testEditableRoundTripsWithoutBinaryFloatingPoint() {
        for code in ["JPY", "USD", "JOD", "CLF"] {
            for value in [Int64(1), 10, 123456, Int64.max] {
                let text = CurrencyMath.editable(minorUnits: value, currencyCode: code)
                XCTAssertEqual(CurrencyMath.parseMinorUnits(text, currencyCode: code), value)
            }
        }
        XCTAssertEqual(CurrencyMath.editable(minorUnits: 1, currencyCode: "JOD"), "0.001")
        XCTAssertEqual(CurrencyMath.editable(minorUnits: Int64.min, currencyCode: "USD"), "-92233720368547758.08")
    }

    func testLocalizedFormattingRetainsCurrencyAndPrecision() {
        let english = CurrencyMath.format(minorUnits: 123456, currencyCode: "JOD", locale: Locale(identifier: "en_US"))
        XCTAssertTrue(english.contains("123.456"), english)
        XCTAssertTrue(english.contains("JOD"), english)
        let arabic = CurrencyMath.format(minorUnits: 100, currencyCode: "USD", locale: Locale(identifier: "ar_JO"))
        XCTAssertFalse(arabic.isEmpty)
    }
}
