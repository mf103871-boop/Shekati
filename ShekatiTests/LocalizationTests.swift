import Foundation
import XCTest
@testable import Shekati

final class LocalizationTests: XCTestCase {
    func testArabicDayCountsFollowPluralCategories() {
        XCTAssertEqual(Localization.arabicDays(1), "يوم واحد")
        XCTAssertEqual(Localization.arabicDays(2), "يومان")
        XCTAssertEqual(Localization.arabicDays(3), "3 أيام")
        XCTAssertEqual(Localization.arabicDays(10), "10 أيام")
        XCTAssertEqual(Localization.arabicDays(11), "11 يومًا")
        XCTAssertEqual(Localization.arabicDays(99), "99 يومًا")
        XCTAssertEqual(Localization.arabicDays(100), "100 يوم")
        XCTAssertEqual(Localization.arabicDays(103), "103 أيام")
        XCTAssertEqual(Localization.arabicDays(365), "365 يومًا")
        XCTAssertEqual(Localization.arabicDays(-15), "15 يومًا")
    }

    func testRelativeDaysAndReminderOffsetsInBothLanguages() {
        XCTAssertEqual(Localization.relativeDays(15, language: .english), "In 15 days")
        XCTAssertEqual(Localization.relativeDays(-15, language: .english), "Overdue by 15 days")
        XCTAssertEqual(Localization.relativeDays(7, language: .arabic), "بعد 7 أيام")
        XCTAssertEqual(Localization.relativeDays(15, language: .arabic), "بعد 15 يومًا")
        XCTAssertEqual(Localization.relativeDays(-30, language: .arabic), "متأخر منذ 30 يومًا")
        XCTAssertEqual(Localization.daysBefore(14, language: .english), "14 days before")
        XCTAssertEqual(Localization.daysBefore(7, language: .arabic), "7 أيام قبل الاستحقاق")
        XCTAssertEqual(Localization.daysBefore(14, language: .arabic), "14 يومًا قبل الاستحقاق")
        XCTAssertEqual(Localization.daysBefore(2, language: .arabic), "يومان قبل الاستحقاق")
    }

    func testEveryArabicEntryIsNonEmptyAndUnknownKeysFallBackToEnglish() {
        for (key, value) in Localization.arabic {
            XCTAssertFalse(key.isEmpty); XCTAssertFalse(value.isEmpty, key)
        }
        XCTAssertEqual(Localization.text("Cancel", language: .arabic), "إلغاء")
        XCTAssertEqual(Localization.text("Cancel", language: .english), "Cancel")
        XCTAssertEqual(Localization.text("Unknown key", language: .arabic), "Unknown key")
    }
}
