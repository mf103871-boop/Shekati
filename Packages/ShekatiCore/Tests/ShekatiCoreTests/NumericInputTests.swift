import XCTest
@testable import ShekatiCore

final class NumericInputTests: XCTestCase {
    func testDisplayNormalizationPreservesNonDigitText() {
        XCTAssertEqual(NumericInput.latinDigits("شيك ٠٠١۲٣ — ５/١٠/۲۰۲۶: USD ٧٫٥"), "شيك 00123 — 5/10/2026: USD 7٫5")
        XCTAssertEqual(NumericInput.latinDigits("٠١٢٣٤٥٦٧٨٩ ۰۱۲۳۴۵۶۷۸۹ ０１２３４５６７８９"), "0123456789 0123456789 0123456789")
        XCTAssertEqual(NumericInput.latinDigits(""), "")
    }

    func testIntegerNormalizesMixedDigitsAndPreservesLeadingZeros() {
        XCTAssertEqual(NumericInput.integer("٠٠0۶７"), "00067")
        XCTAssertEqual(NumericInput.integer("000006"), "000006")
        XCTAssertEqual(NumericInput.integer(""), "")
    }

    func testIntegerRejectsWholeInvalidProposal() {
        for text in ["12a3", "١٢أ٣", "12-3", "+1", "-1", "1.5", "1,5", "١٫٥", "١٬٢٣٤", "1 234", " 123", "123\n", "1/2", "1e3", "١٢🔒٣", "1\u{200F}2"] {
            XCTAssertNil(NumericInput.integer(text), text)
        }
    }

    func testDecimalNormalizesDigitsAndSupportedDecimalSeparators() {
        XCTAssertEqual(NumericInput.decimal("٠٠١٢٫۵۶", fractionDigits: 2), "0012.56")
        XCTAssertEqual(NumericInput.decimal("۱۲,۵", fractionDigits: 2), "12.5")
        XCTAssertEqual(NumericInput.decimal("１２.３４５", fractionDigits: 3), "12.345")
    }

    func testDecimalEditingStatesAndLeadingSeparator() {
        XCTAssertEqual(NumericInput.decimal("", fractionDigits: 2), "")
        XCTAssertEqual(NumericInput.decimal("0", fractionDigits: 2), "0")
        XCTAssertEqual(NumericInput.decimal("١٢٫", fractionDigits: 2), "12.")
        XCTAssertEqual(NumericInput.decimal(".", fractionDigits: 2), "0.")
        XCTAssertEqual(NumericInput.decimal("٫٥", fractionDigits: 2), "0.5")
        XCTAssertEqual(NumericInput.decimal(",25", fractionDigits: 2), "0.25")
        XCTAssertNil(CurrencyMath.parseMinorUnits("12.", currencyCode: "USD"))
        XCTAssertNil(CurrencyMath.parseMinorUnits("0", currencyCode: "USD"))
    }

    func testZeroDecimalCurrenciesAcceptOnlyWholeDigits() {
        XCTAssertEqual(NumericInput.decimal("٠٠١٢", fractionDigits: 0), "0012")
        XCTAssertEqual(NumericInput.decimal("", fractionDigits: 0), "")
        for text in ["12.", "12.0", "12,0", "١٢٫٠", "."] {
            XCTAssertNil(NumericInput.decimal(text, fractionDigits: 0), text)
        }
    }

    func testPrecisionIsRejectedWithoutTruncationOrRounding() {
        XCTAssertEqual(NumericInput.decimal("12.34", fractionDigits: 2), "12.34")
        XCTAssertNil(NumericInput.decimal("12.345", fractionDigits: 2))
        XCTAssertEqual(NumericInput.decimal("١٢٫٣٤٥", fractionDigits: 3), "12.345")
        XCTAssertNil(NumericInput.decimal("١٢٫٣٤٥٦", fractionDigits: 3))
        XCTAssertEqual(NumericInput.decimal("0.0001", fractionDigits: 4), "0.0001")
        XCTAssertNil(NumericInput.decimal("12", fractionDigits: -1))
    }

    func testDecimalRejectsLettersSignsGroupingAndExponents() {
        for text in ["12a3", "١٢أ٣", "12-3", "-1", "+1", "−1", "1e3", "1E3", "NaN", "USD 1", "1 234", "1\u{00A0}234", "١٬٢٣٤٫٥٠", "1,234.50", "1,234,567", "1.2.3", "١٫٢,٣", "1/2", " 12", "12\n", "1\u{200F}2"] {
            XCTAssertNil(NumericInput.decimal(text, fractionDigits: 3), text)
        }
    }

    func testNumericEditingLeavesOverflowValidationToExactAmountParser() throws {
        let validBoundary = "٩٢٢٣٣٧٢٠٣٦٨٥٤٧٧٥٨٫٠٧"
        let overflow = "٩٢٢٣٣٧٢٠٣٦٨٥٤٧٧٥٨٫٠٨"
        let normalizedBoundary = try XCTUnwrap(NumericInput.decimal(validBoundary, fractionDigits: 2))
        let normalizedOverflow = try XCTUnwrap(NumericInput.decimal(overflow, fractionDigits: 2))
        XCTAssertEqual(normalizedBoundary, "92233720368547758.07")
        XCTAssertEqual(normalizedOverflow, "92233720368547758.08")
        XCTAssertEqual(CurrencyMath.parseMinorUnits(normalizedBoundary, currencyCode: "USD"), Int64.max)
        XCTAssertNil(CurrencyMath.parseMinorUnits(normalizedOverflow, currencyCode: "USD"))
        XCTAssertEqual(NumericInput.integer("999999999999999999999999999999"), "999999999999999999999999999999")
    }
}
