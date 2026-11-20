/// Normalizes numeric text before it enters an editable field.
/// Invalid proposals are rejected as a whole, so pasting `12-3` never becomes `123`.
public enum NumericInput {
    /// Maps every Unicode decimal-digit script to Western digits.
    /// Other characters remain unchanged, making this suitable for display text too.
    public static func latinDigits(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if let digit = westernDigit(scalar) {
                result.append(digit)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Allows an empty editing value or a sequence of digits, preserving leading zeros.
    public static func integer(_ proposed: String) -> String? {
        var result = ""
        for scalar in proposed.unicodeScalars {
            guard let digit = westernDigit(scalar) else { return nil }
            result.append(digit)
        }
        return result
    }

    /// Allows an unsigned amount with at most the currency's fractional precision.
    /// A comma, period, or Arabic decimal separator is normalized to a period.
    /// Empty values and a trailing decimal separator are allowed while editing;
    /// final positive-value and overflow checks belong to `CurrencyMath.parseMinorUnits`.
    public static func decimal(_ proposed: String, fractionDigits: Int) -> String? {
        guard fractionDigits >= 0 else { return nil }
        var result = ""
        var hasSeparator = false
        var fractionalCount = 0
        for scalar in proposed.unicodeScalars {
            if let digit = westernDigit(scalar) {
                if hasSeparator {
                    fractionalCount += 1
                    guard fractionalCount <= fractionDigits else { return nil }
                }
                result.append(digit)
            } else if scalar.value == 0x002E || scalar.value == 0x002C || scalar.value == 0x066B {
                guard fractionDigits > 0, !hasSeparator else { return nil }
                hasSeparator = true
                if result.isEmpty { result = "0" }
                result.append(".")
            } else {
                return nil
            }
        }
        return result
    }

    private static func westernDigit(_ scalar: Unicode.Scalar) -> Character? {
        if scalar.isASCII { return (48...57).contains(scalar.value) ? Character(scalar) : nil }
        guard scalar.properties.numericType == .decimal, let digit = scalar.properties.numericValue else { return nil }
        return Character(String(Int(digit)))
    }
}
