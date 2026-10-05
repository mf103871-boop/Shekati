import Foundation

public enum CurrencyMath {
    /// ISO 4217 minor-unit exponents for monetary currencies; standard currencies otherwise use two.
    public static func fractionDigits(for code: String) -> Int {
        switch code.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF": return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND": return 3
        case "CLF", "UYW": return 4
        default: return 2
        }
    }

    /// Parses exact integer minor units, never floating point. Group separators and signs are rejected.
    public static func parseMinorUnits(_ text: String, currencyCode: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = ""
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 48...57: normalized.unicodeScalars.append(scalar)
            case 0x0660...0x0669: normalized.append(String(scalar.value - 0x0660))
            case 0x06F0...0x06F9: normalized.append(String(scalar.value - 0x06F0))
            case 46, 44, 0x066B: normalized.append(".")
            default: return nil
            }
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty, parts[0].allSatisfy(\.isNumber) else { return nil }
        let digits = fractionDigits(for: currencyCode)
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= digits, (parts.count == 1 || !fraction.isEmpty), fraction.allSatisfy(\.isNumber) else { return nil }
        let padded = fraction + String(repeating: "0", count: digits - fraction.count)
        let raw = String(parts[0]) + padded
        var value: Int64 = 0
        for character in raw {
            guard let digit = character.wholeNumberValue else { return nil }
            let scaled = value.multipliedReportingOverflow(by: 10)
            guard !scaled.overflow else { return nil }
            let added = scaled.partialValue.addingReportingOverflow(Int64(digit))
            guard !added.overflow else { return nil }
            value = added.partialValue
        }
        return value > 0 ? value : nil
    }

    public static func format(minorUnits: Int64, currencyCode: String, locale: Locale) -> String {
        let digits = fractionDigits(for: currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.uppercased()
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let decimal = Decimal(minorUnits) / powerOfTen(digits)
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(editable(minorUnits: minorUnits, currencyCode: currencyCode)) \(currencyCode.uppercased())"
    }

    public static func editable(minorUnits: Int64, currencyCode: String) -> String {
        let digits = fractionDigits(for: currencyCode)
        var magnitude = String(minorUnits.magnitude)
        if digits > 0 {
            if magnitude.count <= digits { magnitude = String(repeating: "0", count: digits + 1 - magnitude.count) + magnitude }
            magnitude.insert(".", at: magnitude.index(magnitude.endIndex, offsetBy: -digits))
        }
        return (minorUnits < 0 ? "-" : "") + magnitude
    }

    /// Spreadsheet-style text: Western digits, no symbol or grouping, no trailing fractional zeros.
    /// `950.000` JOD becomes `950` and `731.250` becomes `731.25`.
    public static func plain(minorUnits: Int64, currencyCode: String) -> String {
        var text = editable(minorUnits: minorUnits, currencyCode: currencyCode)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func powerOfTen(_ exponent: Int) -> Decimal {
        (0..<exponent).reduce(Decimal(1)) { value, _ in value * 10 }
    }
}
