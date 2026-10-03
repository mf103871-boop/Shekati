import XCTest
import ShekatiCore
@testable import Shekati

final class ReminderPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-03T08:00:00Z")! }
    private var settings: ReminderSettings {
        ReminderSettings(offsets: [3, 1, 0], hour: 9, minute: 0, dailySummary: false, hideDetails: false, languageCode: "en")
    }
    private func input(day: String, status: ChequeStatus = .pending, enabled: Bool = true,
                       offsets: [Int]? = nil, id: UUID = UUID()) -> ChequeReminderInput {
        ChequeReminderInput(snapshot: ChequeSnapshot(id: id, direction: .outgoing, status: status,
                                                     amountMinorUnits: 125_000, currencyCode: "JOD",
                                                     dueDate: LocalDay(iso: day)!, number: "001234", bank: "Example Bank", party: "Private Person"),
                            enabled: enabled, offsets: offsets)
    }

    func testCustomOffsetsOverrideDefaultsAndStableIDsSurviveDateEdit() {
        let id = UUID()
        let original = ReminderPlanner.makePlan(inputs: [input(day: "2026-10-13", offsets: [7, 7], id: id)], settings: settings, now: now, calendar: calendar)
        let edited = ReminderPlanner.makePlan(inputs: [input(day: "2026-10-14", offsets: [7], id: id)], settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(original.items.count, 1)
        XCTAssertEqual(original.items.first?.id, edited.items.first?.id)
        XCTAssertNotEqual(original.items.first?.fireDate, edited.items.first?.fireDate)
        XCTAssertEqual(LocalDay(date: original.items[0].fireDate, calendar: calendar).iso, "2026-10-06")
    }

    func testChequeTimeOverrideAndInheritedTimeDoNotChangeSummaryTime() {
        var config = settings
        config.offsets = [0]
        config.dailySummary = true
        var custom = input(day: "2026-10-04")
        custom.hour = 15
        custom.minute = 25
        let inherited = input(day: "2026-10-04")
        let plan = ReminderPlanner.makePlan(inputs: [custom, inherited], settings: config, now: now, calendar: calendar)
        let customReminder = plan.items.first { $0.chequeID == custom.snapshot.id }!
        let inheritedReminder = plan.items.first { $0.chequeID == inherited.snapshot.id }!
        XCTAssertEqual(calendar.component(.hour, from: customReminder.fireDate), 15)
        XCTAssertEqual(calendar.component(.minute, from: customReminder.fireDate), 25)
        XCTAssertEqual(calendar.component(.hour, from: inheritedReminder.fireDate), 9)
        XCTAssertEqual(calendar.component(.minute, from: inheritedReminder.fireDate), 0)
        XCTAssertTrue(plan.items.filter { $0.kind == .dailySummary }.allSatisfy {
            calendar.component(.hour, from: $0.fireDate) == 9 && calendar.component(.minute, from: $0.fireDate) == 0
        })
    }

    func testSettledCancelledDisabledAndPastRemindersHaveNoQueueEntries() {
        let inputs = [input(day: "2026-10-15", status: .settled), input(day: "2026-10-15", status: .cancelled),
                      input(day: "2026-10-15", enabled: false), input(day: "2026-10-02")]
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now, calendar: calendar)
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertNil(plan.firstUncoveredDate)
    }

    func testOverflowReservesNoticeWithinTotalBudgetAndReportsFirstOmittedEvent() {
        var config = settings
        config.offsets = [0]
        let start = LocalDay(iso: "2026-10-03")!
        let inputs = (1...80).map { distance in input(day: start.adding(days: distance, calendar: calendar).iso) }
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: config, now: now, calendar: calendar)
        XCTAssertEqual(plan.items.count, 60)
        XCTAssertEqual(plan.items.filter { $0.kind == .cheque }.count, 59)
        XCTAssertEqual(plan.items.filter { $0.kind == .replenishment }.count, 1)
        let firstOmitted = start.adding(days: 60, calendar: calendar)
        XCTAssertEqual(plan.firstUncoveredDate.map { LocalDay(date: $0, calendar: calendar) }, firstOmitted)
        XCTAssertLessThan(plan.items.first { $0.kind == .replenishment }!.fireDate, plan.firstUncoveredDate!)
        XCTAssertEqual(plan.items, ReminderPlanner.makePlan(inputs: Array(inputs.reversed()), settings: config, now: now, calendar: calendar).items)
    }

    func testImminentOverflowNoticeDoesNotWaitUntilAfterCutoff() {
        var config = settings
        config.offsets = [0]
        let soon = now.addingTimeInterval(3_590) // Ten seconds before the configured reminder time.
        let inputs = (0..<80).map { _ in input(day: "2026-10-03") }
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: config, now: soon, calendar: calendar)
        let notice = plan.items.first { $0.kind == .replenishment }!
        XCTAssertGreaterThan(notice.fireDate, soon)
        XCTAssertLessThan(notice.fireDate, plan.firstUncoveredDate!)
    }

    func testDailySummariesUseNextThreeDaysAndDeclareRollingCoverage() {
        var config = settings
        config.dailySummary = true
        config.offsets = []
        let plan = ReminderPlanner.makePlan(inputs: [input(day: "2026-10-06"), input(day: "2026-10-07")], settings: config, now: now, calendar: calendar)
        let todaySummary = plan.items.first { $0.id == "shekati.summary.2026-10-03" }!
        XCTAssertEqual(todaySummary.body, "Due today: 0 · Overdue: 0 · Next 3 days: 1")
        XCTAssertEqual(plan.items.filter { $0.kind == .dailySummary }.count, 30)
        XCTAssertEqual(plan.items.filter { $0.kind == .replenishment }.count, 1)
        XCTAssertEqual(plan.firstUncoveredDate.map { LocalDay(date: $0, calendar: calendar).iso }, "2026-11-02")
        XCTAssertLessThanOrEqual(plan.items.count, ReminderPlanner.notificationBudget)
    }

    func testHiddenDetailsNeverContainChequeNumberPartyOrAmount() {
        var config = settings
        config.hideDetails = true
        config.dailySummary = true
        let plan = ReminderPlanner.makePlan(inputs: [input(day: "2026-10-04")], settings: config, now: now, calendar: calendar)
        for reminder in plan.items {
            XCTAssertFalse(reminder.body.contains("001234"))
            XCTAssertFalse(reminder.body.contains("Private Person"))
            XCTAssertFalse(reminder.body.contains("125"))
        }
    }

    func testCivilDayOffsetsKeepNineAMAcrossDaylightSavingChange() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var config = settings
        config.offsets = [1, 0]
        let beforeChange = ISO8601DateFormatter().date(from: "2026-03-06T12:00:00Z")!
        let plan = ReminderPlanner.makePlan(inputs: [input(day: "2026-03-08")], settings: config, now: beforeChange, calendar: newYork)
        XCTAssertEqual(plan.items.map { newYork.component(.hour, from: $0.fireDate) }, [9, 9])
        XCTAssertEqual(plan.items[1].fireDate.timeIntervalSince(plan.items[0].fireDate), 23 * 3_600)
    }

    func testHijriDeviceCalendarDoesNotChangeGregorianChequeDates() {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = calendar.timeZone
        let inputs = [input(day: "2026-10-09")]
        let gregorianPlan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now, calendar: calendar)
        let islamicPlan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now, calendar: islamic)
        XCTAssertEqual(gregorianPlan.items, islamicPlan.items)
    }

    func testAcceptanceInspectionReportsRejectedOrWrongTimeReminders() {
        let plan = ReminderPlanner.makePlan(inputs: [input(day: "2026-10-09")], settings: settings, now: now, calendar: calendar)
        var accepted = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0.fireDate) })
        accepted[plan.items[0].id] = nil
        accepted[plan.items[1].id] = plan.items[1].fireDate.addingTimeInterval(3_600)
        let result = ReminderPlanner.confirm(plan: plan, acceptedDates: accepted)
        XCTAssertEqual(result.acceptedCount, plan.items.count - 2)
        XCTAssertEqual(result.firstUncoveredDate, plan.items[0].fireDate)
        let complete = ReminderPlanner.confirm(plan: plan, acceptedDates: Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0.fireDate) }))
        XCTAssertEqual(complete.acceptedCount, plan.items.count)
        XCTAssertNil(complete.firstUncoveredDate)
    }
}
