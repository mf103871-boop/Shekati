import Foundation
import ShekatiCore

/// UI-only formatter reuse. The exact money parser remains independent of mutable formatters.
@MainActor
enum DisplayFormatting {
    private static var amounts: [String: NumberFormatter] = [:]
    private static var days: [String: DateFormatter] = [:]
    private static var timestamps: [String: DateFormatter] = [:]

    static func amount(minorUnits: Int64, currencyCode: String, locale: Locale) -> String {
        let key = "\(currencyCode)|\(locale.identifier)"
        let formatter: NumberFormatter
        if let cached = amounts[key] { formatter = cached }
        else {
            let created = NumberFormatter()
            created.locale = locale
            created.numberStyle = .currency
            created.currencyCode = currencyCode
            let digits = CurrencyMath.fractionDigits(for: currencyCode)
            created.minimumFractionDigits = digits
            created.maximumFractionDigits = digits
            amounts[key] = created
            formatter = created
        }
        let divisor = (0..<CurrencyMath.fractionDigits(for: currencyCode)).reduce(Decimal(1)) { value, _ in value * 10 }
        let value = NSDecimalNumber(decimal: Decimal(minorUnits) / divisor)
        return NumericInput.latinDigits(formatter.string(from: value) ?? CurrencyMath.editable(minorUnits: minorUnits, currencyCode: currencyCode))
    }

    static func day(_ day: LocalDay, locale: Locale, zone: TimeZone = .current) -> String {
        let key = "\(locale.identifier)|\(zone.identifier)"
        let formatter: DateFormatter
        if let cached = days[key] { formatter = cached }
        else {
            let created = DateFormatter()
            created.locale = locale
            created.calendar = Calendar(identifier: .gregorian)
            created.timeZone = zone
            created.dateFormat = "dd/MM/yyyy"
            days[key] = created
            formatter = created
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return NumericInput.latinDigits(formatter.string(from: day.date(calendar: calendar)))
    }

    static func timestamp(_ date: Date, locale: Locale, zone: TimeZone = .current) -> String {
        let key = "\(locale.identifier)|\(zone.identifier)"
        let formatter: DateFormatter
        if let cached = timestamps[key] { formatter = cached }
        else {
            let created = DateFormatter()
            created.locale = locale
            created.calendar = Calendar(identifier: .gregorian)
            created.timeZone = zone
            created.dateStyle = .medium
            created.timeStyle = .short
            timestamps[key] = created
            formatter = created
        }
        return NumericInput.latinDigits(formatter.string(from: date))
    }

    static func count(_ value: Int, locale: Locale) -> String {
        NumericInput.latinDigits(value.formatted(.number.locale(locale)))
    }
}
