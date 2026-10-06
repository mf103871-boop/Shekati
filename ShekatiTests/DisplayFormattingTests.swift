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
                        let displayed = DisplayFormatting.amount(minorUnits: value, currencyCode: code, locale: locale)
                        XCTAssertEqual(displayed,
                                       CurrencyMath.format(minorUnits: value, currencyCode: code, locale: locale),
                                       "Exact money display must be preserved for \(code), \(locale.identifier), \(value)")
                        assertWesternDigits(displayed)
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
            XCTAssertEqual(actual, "04/10/2026", "The user's calendar must not change the cheque's civil date or digit style")
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
                let displayed = DisplayFormatting.timestamp(instant, locale: locale, zone: zone)
                XCTAssertEqual(displayed, NumericInput.latinDigits(formatter.string(from: instant)))
                assertWesternDigits(displayed)
            }
        }
    }

    func testCountsUseWesternDigitsForArabicDeviceLocales() {
        for locale in [Locale(identifier: "ar_JO"), Locale(identifier: "ar_SA"), Locale(identifier: "en_US"), AppLanguage.arabic.locale] {
            for count in [0, 1, 1234, 12_345_678] {
                let displayed = DisplayFormatting.count(count, locale: locale)
                assertWesternDigits(displayed)
                XCTAssertEqual(String(displayed.filter { $0.isASCII && $0.isNumber }), String(count))
            }
        }
    }

    func testArabicAppLocaleKeepsArabicLanguageAndWesternDigits() throws {
        XCTAssertEqual(AppLanguage.arabic.locale.language.languageCode?.identifier, "ar")
        XCTAssertEqual(AppLanguage.arabic.locale.numberingSystem.identifier, "latn")
        let day = try XCTUnwrap(LocalDay(iso: "2026-10-06"))
        XCTAssertEqual(DisplayFormatting.day(day, locale: AppLanguage.arabic.locale), "06/10/2026")
        XCTAssertEqual(Localization.text("Within 7 days", language: .arabic), "خلال 7 أيام")
    }

    func testReminderRendersLegacyChequeDigitsWithoutChangingTheRecord() throws {
        let cheque = ChequeSnapshot(direction: .outgoing, amountMinorUnits: 123_456, currencyCode: "JOD",
                                    dueDate: try XCTUnwrap(LocalDay(iso: "2026-10-06")), number: "٠٠۱۲٣۴")
        let settings = ReminderSettings(offsets: [0], hour: 9, minute: 0, dailySummary: false,
                                        hideDetails: false, languageCode: "ar")
        let content = ReminderPlanner.chequeContent(cheque: cheque, settings: settings, offset: 0)
        XCTAssertTrue(content.body.contains("#001234"), content.body)
        XCTAssertTrue(content.body.contains("2026-10-06"), content.body)
        assertWesternDigits(content.body)
        XCTAssertEqual(cheque.number, "٠٠۱۲٣۴", "Display normalization must not rewrite an existing record")
    }

    private func assertWesternDigits(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for scalar in text.unicodeScalars where CharacterSet.decimalDigits.contains(scalar) {
            XCTAssertTrue((48...57).contains(scalar.value), "Non-Western digit in \(text)", file: file, line: line)
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
        return NumericInput.latinDigits(formatter.string(from: day.date(calendar: calendar)))
    }
}
