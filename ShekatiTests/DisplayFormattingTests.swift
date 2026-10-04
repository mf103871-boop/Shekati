import Foundation
import XCTest
import ShekatiCore
@testable import Shekati

@MainActor
final class DisplayFormattingTests: XCTestCase {
    func testCachedAmountsMatchExactMoneyFormattingAcrossCurrenciesAndLocales() {
        let locales = [Locale(identifier: "en_US"), Locale(identifier: "ar_JO"), Locale(identifier: "ar_SA")]
        let amounts: [Int64] = [0, 1, 125_501, -1, Int64.max]
        // Interleave locales/currencies, then repeat in reverse to detect cache contamination.
        for codes in [["JPY", "USD", "JOD"], ["JOD", "USD", "JPY"]] {
            for code in codes {
                for locale in locales {
                    for value in amounts {
                        XCTAssertEqual(DisplayFormatting.amount(minorUnits: value, currencyCode: code, locale: locale),
                                       CurrencyMath.format(minorUnits: value, currencyCode: code, locale: locale),
                                       "Exact money display must be preserved for \(code), \(locale.identifier), \(value)")
                    }
                }
            }
        }
    }

    func testCachedCivilDaysStayTheSameAcrossTimeZonesAndDaylightSavingBoundaries() throws {
        let zones = try ["Pacific/Kiritimati", "America/Los_Angeles", "Asia/Amman"].map { try XCTUnwrap(TimeZone(identifier: $0)) }
        for iso in ["2026-03-08", "2026-03-29", "2026-11-01"] {
            let day = try XCTUnwrap(LocalDay(iso: iso))
            let expectedNumeric = "\(iso.suffix(2))/\(iso.dropFirst(5).prefix(2))/\(iso.prefix(4))"
            for zone in zones {
                let displayed = DisplayFormatting.day(day, locale: Locale(identifier: "en_US"), zone: zone)
                XCTAssertEqual(displayed, expectedNumeric)
                XCTAssertEqual(displayed, freshDay(day, locale: Locale(identifier: "en_US"), zone: zone))
            }
        }
    }

    func testGregorianCivilDayOverridesHijriAndBuddhistLocaleCalendarsWithoutLeakingLocale() throws {
        let day = try XCTUnwrap(LocalDay(iso: "2026-10-04"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Amman"))
        let locales = [Locale(identifier: "ar_SA@calendar=islamic"), Locale(identifier: "th_TH@calendar=buddhist"),
                       Locale(identifier: "en_US"), Locale(identifier: "ar_JO"), Locale(identifier: "en_US")]
        for locale in locales {
            let actual = DisplayFormatting.day(day, locale: locale, zone: zone)
            XCTAssertEqual(actual, freshDay(day, locale: locale, zone: zone))
            let numeric = String(actual.compactMap { character -> Character? in
                if let digit = character.wholeNumberValue { return Character(String(digit)) }
                return character == "/" ? character : nil
            })
            XCTAssertEqual(numeric, "04/10/2026", "The user's calendar must not change the cheque's civil date")
        }
    }

    func testCachedTimestampsMatchFreshGregorianFormattersAfterZoneAndLocaleChanges() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 45)))
        let zones = try ["Asia/Amman", "America/Los_Angeles", "Pacific/Kiritimati", "Asia/Amman"].map { try XCTUnwrap(TimeZone(identifier: $0)) }
        for zone in zones {
            for locale in [Locale(identifier: "en_US"), Locale(identifier: "ar_JO"), Locale(identifier: "ar_SA@calendar=islamic")] {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = zone
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                XCTAssertEqual(DisplayFormatting.timestamp(instant, locale: locale, zone: zone), formatter.string(from: instant))
            }
        }
    }

    private func freshDay(_ day: LocalDay, locale: Locale, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "dd/MM/yyyy"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return formatter.string(from: day.date(calendar: calendar))
    }
}
