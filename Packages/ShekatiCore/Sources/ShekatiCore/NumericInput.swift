/// Normalizes numeric text before it enters an editable field.
/// Invalid proposals are rejected as a whole, so pasting `12-3` never becomes `123`.
public enum NumericInput {
    /// Replaces Arabic-Indic, Persian, and fullwidth digits with Western digits.
    /// Other characters remain unchanged, making this suitable for display text too.
    public static func latinDigits(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if let digit = westernDigit(scalar.value) {
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
            guard let digit = westernDigit(scalar.value) else { return nil }
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
            if let digit = westernDigit(scalar.value) {
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

    private static func westernDigit(_ value: UInt32) -> Character? {
        let digit: UInt32
        switch value {
        case 0x0030...0x0039: digit = value - 0x0030
        case 0x0660...0x0669: digit = value - 0x0660
        case 0x06F0...0x06F9: digit = value - 0x06F0
        case 0xFF10...0xFF19: digit = value - 0xFF10
        default: return nil
        }
        return Character(String(digit))
    }
}
