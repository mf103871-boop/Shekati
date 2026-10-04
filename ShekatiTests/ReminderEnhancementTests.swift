import Foundation
import UserNotifications
import XCTest
import ShekatiCore
@testable import Shekati

final class ReminderEnhancementTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-10-04T08:00:00Z")! }
    private var settings: ReminderSettings {
        ReminderSettings(offsets: [3, 1, 0], hour: 9, minute: 0, dailySummary: false,
                         hideDetails: false, languageCode: "en")
    }

    func testRefreshKeyCannotCollideWhenSeparatorsMoveBetweenNumberAndParty() {
        var original = input(day: LocalDay(iso: "2026-10-05")!)
        original.snapshot.number = "123|Ahmed"
        original.snapshot.party = "Ali"
        var edited = original
        edited.snapshot.number = "123"
        edited.snapshot.party = "Ahmed|Ali"
        XCTAssertNotEqual(refreshKey([original]), refreshKey([edited]))
        original.snapshot.number = "123;Ahmed"
        edited.snapshot.number = "123"
        edited.snapshot.party = ";Ahmed|Ali"
        XCTAssertNotEqual(refreshKey([original]), refreshKey([edited]))
    }

    func testRefreshKeyIgnoresRecordOrderNotesBankAndManualOrder() {
        let first = input(day: LocalDay(iso: "2026-10-05")!)
        let second = input(day: LocalDay(iso: "2026-10-06")!)
        var noteEdit = first
        noteEdit.snapshot.notes = "A note containing | and ;"
        noteEdit.snapshot.bank = "New bank label"
        noteEdit.snapshot.branch = "New branch"
        noteEdit.snapshot.manualRank = 8_000
        XCTAssertEqual(refreshKey([first, second]), refreshKey([second, noteEdit]))
    }

    func testRefreshKeyTracksGlobalPermissionSummaryClockPrivacyLanguageAndDefaultOffsets() {
        let cheque = input(day: LocalDay(iso: "2026-10-05")!)
        let baseline = refreshKey([cheque])
        XCTAssertNotEqual(baseline, refreshKey([cheque], authorization: 1))
        XCTAssertNotEqual(baseline, refreshKey([cheque], dayRevision: 1))
        for property in 0..<6 {
            var changed = settings
            switch property {
            case 0: changed.dailySummary = true
            case 1: changed.hour = 10
            case 2: changed.minute = 30
            case 3: changed.hideDetails = true
            case 4: changed.languageCode = "ar"
            default: changed.offsets = [7, 1, 0]
            }
            XCTAssertNotEqual(baseline, refreshKey([cheque], settings: changed))
        }
    }

    func testRefreshKeyTracksFinancialFieldsAndIndividualReminderOverrides() {
        let cheque = input(day: LocalDay(iso: "2026-10-05")!)
        let baseline = refreshKey([cheque])
        for property in 0..<10 {
            var changed = cheque
            switch property {
            case 0: changed.snapshot.amountMinorUnits += 1
            case 1: changed.snapshot.dueDate = changed.snapshot.dueDate.adding(days: 1)
            case 2: changed.snapshot.direction = .outgoing
            case 3: changed.snapshot.status = .settled
            case 4: changed.snapshot.currencyCode = "USD"
            case 5: changed.snapshot.number = "000987"
            case 6: changed.snapshot.party = "Another party"
            case 7: changed.enabled = false
            case 8: changed.offsets = []
            default: changed.hour = 12; changed.minute = 15
            }
            XCTAssertNotEqual(baseline, refreshKey([changed]))
        }
    }

    func testSnoozesSummariesChequeAlertsAndCoverageShareOneSixtyRequestBudget() throws {
        var configuration = settings
        configuration.dailySummary = true
        let today = LocalDay(date: now, calendar: calendar)
        let inputs = (1...20).map { input(day: today.adding(days: $0, calendar: calendar)) }
        let snoozed = inputs.map {
            SnoozedCheque(chequeID: $0.snapshot.id, fireDate: now.addingTimeInterval(1_800), dueDateISO: $0.snapshot.dueDate.iso)
        }
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: configuration, now: now,
                                            calendar: calendar, snoozed: snoozed)
        XCTAssertEqual(plan.items.count, 60)
        XCTAssertEqual(Set(plan.items.map(\.id)).count, 60)
        XCTAssertEqual(plan.items.filter { $0.kind == .replenishment }.count, 1)
        XCTAssertTrue(plan.items.contains { $0.kind == .snooze })
        XCTAssertTrue(plan.items.contains { $0.kind == .cheque })
        XCTAssertTrue(plan.items.contains { $0.kind == .dailySummary })
        let uncovered = try XCTUnwrap(plan.firstUncoveredDate)
        XCTAssertLessThan(try XCTUnwrap(plan.items.first { $0.kind == .replenishment }).fireDate, uncovered)
        let reversed = ReminderPlanner.makePlan(inputs: Array(inputs.reversed()), settings: configuration,
                                                now: now, calendar: calendar, snoozed: Array(snoozed.reversed()))
        XCTAssertEqual(plan.items, reversed.items)
        XCTAssertEqual(plan.firstUncoveredDate, reversed.firstUncoveredDate)
    }

    func testSnoozeIsRemovedForSettledCancelledDisabledEditedDueDateAndExpiredTime() {
        let day = LocalDay(iso: "2026-10-05")!
        let valid = input(day: day)
        var settled = input(day: day)
        settled.snapshot.status = .settled
        var cancelled = input(day: day)
        cancelled.snapshot.status = .cancelled
        var disabled = input(day: day)
        disabled.enabled = false
        var edited = input(day: day)
        edited.snapshot.dueDate = day.adding(days: 1, calendar: calendar)
        let expired = input(day: day)
        let inputs = [valid, settled, cancelled, disabled, edited, expired]
        let snoozed = inputs.map {
            SnoozedCheque(chequeID: $0.snapshot.id,
                         fireDate: $0.snapshot.id == expired.snapshot.id ? now.addingTimeInterval(-1) : now.addingTimeInterval(3_600),
                         dueDateISO: day.iso)
        }
        let plan = ReminderPlanner.makePlan(inputs: inputs, settings: settings, now: now,
                                            calendar: calendar, snoozed: snoozed)
        XCTAssertEqual(plan.items.filter { $0.kind == .snooze }.map(\.chequeID), [valid.snapshot.id])
    }

    func testRepeatedSnoozeProducesOnlyTheLatestRequestAndHiddenDetailsStayHidden() throws {
        var configuration = settings
        configuration.hideDetails = true
        let cheque = input(day: LocalDay(iso: "2026-10-05")!)
        let latestDate = now.addingTimeInterval(7_200)
        let snoozed = [SnoozedCheque(chequeID: cheque.snapshot.id, fireDate: now.addingTimeInterval(3_600), dueDateISO: cheque.snapshot.dueDate.iso),
                       SnoozedCheque(chequeID: cheque.snapshot.id, fireDate: latestDate, dueDateISO: cheque.snapshot.dueDate.iso)]
        let plan = ReminderPlanner.makePlan(inputs: [cheque], settings: configuration, now: now,
                                            calendar: calendar, snoozed: snoozed)
        let reminder = try XCTUnwrap(plan.items.first { $0.kind == .snooze })
        XCTAssertEqual(plan.items.filter { $0.kind == .snooze }.count, 1)
        XCTAssertEqual(reminder.fireDate, latestDate)
        XCTAssertFalse(reminder.body.contains(cheque.snapshot.party))
        XCTAssertFalse(reminder.body.contains(cheque.snapshot.number))
        XCTAssertFalse(reminder.body.contains(cheque.snapshot.dueDate.iso))
        let fingerprint = ReminderRequestPolicy.signature(input: cheque, settings: configuration)
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertTrue(fingerprint.allSatisfy { $0.isHexDigit })
        XCTAssertFalse(fingerprint.contains(cheque.snapshot.number))
    }

    func testUnchangedCalendarRequestMatchesButEditedDatePrivateDetailsAndTimingDoNot() {
        let fireDate = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 86_400).rounded(.up))
        let input = input(day: LocalDay(date: fireDate))
        let signature = ReminderRequestPolicy.signature(input: input, settings: settings)
        let item = item(input: input, fireDate: fireDate)
        let request = calendarRequest(item: item, signature: signature)
        XCTAssertTrue(ReminderRequestPolicy.matches(request, item: item, signature: signature))
        var changedDate = item
        changedDate.fireDate = fireDate.addingTimeInterval(86_400)
        XCTAssertFalse(ReminderRequestPolicy.matches(request, item: changedDate, signature: signature))
        var hidden = settings
        hidden.hideDetails = true
        let hiddenContent = ReminderPlanner.chequeContent(cheque: input.snapshot, settings: hidden, offset: 0)
        var privateItem = item
        privateItem.title = hiddenContent.title
        privateItem.body = hiddenContent.body
        XCTAssertFalse(ReminderRequestPolicy.matches(request, item: privateItem,
                                                      signature: ReminderRequestPolicy.signature(input: input, settings: hidden)))
        var changedInput = input
        changedInput.minute = 15
        XCTAssertFalse(ReminderRequestPolicy.matches(request, item: item,
                                                      signature: ReminderRequestPolicy.signature(input: changedInput, settings: settings)))
    }

    func testIntervalSnoozeAndCoverageRequireTheirActualFutureDateAndNonRepeatingTrigger() {
        let fireDate = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3_600).rounded(.up))
        let input = input(day: LocalDay(date: fireDate))
        let signature = ReminderRequestPolicy.signature(input: input, settings: settings)
        for kind in [ReminderKind.snooze, .replenishment] {
            var planned = item(input: input, fireDate: fireDate)
            planned.kind = kind
            if kind == .replenishment {
                planned.id = "shekati.coverage"
                planned.chequeID = nil
                planned.title = "Refresh your cheque reminders"
                planned.body = "Prepare future reminders."
            } else {
                planned.id = "shekati.snooze.\(input.snapshot.id.uuidString)"
            }
            let request = intervalRequest(item: planned, signature: signature, fireDate: fireDate)
            XCTAssertTrue(ReminderRequestPolicy.matches(request, item: planned, signature: signature), kind.rawValue)
            var wrongDate = planned
            wrongDate.fireDate = fireDate.addingTimeInterval(600)
            XCTAssertFalse(ReminderRequestPolicy.matches(request, item: wrongDate, signature: signature), kind.rawValue)
            let repeating = intervalRequest(item: planned, signature: signature, fireDate: fireDate, repeats: true)
            XCTAssertFalse(ReminderRequestPolicy.matches(repeating, item: planned, signature: signature), kind.rawValue)
        }
    }

    func testUnansweredChequeAlertSurvivesOpeningEditingNotesAndPassingItsDueDay() {
        let cheque = input(day: LocalDay(iso: "2026-10-04")!)
        let reminder = item(input: cheque, fireDate: now.addingTimeInterval(3_600))
        let signature = ReminderRequestPolicy.signature(input: cheque, settings: settings)
        var notesOnly = cheque
        notesOnly.snapshot.notes = "An unrelated note"
        notesOnly.snapshot.manualRank = 900
        XCTAssertEqual(signature, ReminderRequestPolicy.signature(input: notesOnly, settings: settings))
        XCTAssertTrue(isCurrent(reminder, signature: signature, inputs: [notesOnly], settings: settings))
        let afterDue = now.addingTimeInterval(2 * 86_400)
        XCTAssertTrue(ReminderPlanner.makePlan(inputs: [notesOnly], settings: settings, now: afterDue, calendar: calendar).items.isEmpty)
        XCTAssertTrue(isCurrent(reminder, signature: signature, inputs: [notesOnly], settings: settings))
        let otherCheque = input(day: LocalDay(iso: "2026-10-08")!)
        XCTAssertTrue(isCurrent(reminder, signature: signature, inputs: [notesOnly, otherCheque], settings: settings))
    }

    func testDeliveredChequeAlertIsRemovedForSettlementDeletionDisabledReminderDueDateEditAndPrivacyChange() {
        let cheque = input(day: LocalDay(iso: "2026-10-04")!)
        let reminder = item(input: cheque, fireDate: now.addingTimeInterval(3_600))
        let signature = ReminderRequestPolicy.signature(input: cheque, settings: settings)
        var settled = cheque
        settled.snapshot.status = .settled
        var disabled = cheque
        disabled.enabled = false
        var edited = cheque
        edited.snapshot.dueDate = cheque.snapshot.dueDate.adding(days: 1, calendar: calendar)
        var amountEdited = cheque
        amountEdited.snapshot.amountMinorUnits += 1
        var changedDays = cheque
        changedDays.offsets = [1]
        for changed in [settled, disabled, edited, amountEdited, changedDays] {
            XCTAssertFalse(isCurrent(reminder, signature: signature, inputs: [changed], settings: settings))
        }
        XCTAssertFalse(isCurrent(reminder, signature: signature, inputs: [], settings: settings))
        var hidden = settings
        hidden.hideDetails = true
        XCTAssertFalse(isCurrent(reminder, signature: signature, inputs: [cheque], settings: hidden))
    }

    func testSignaturelessHiddenDeliveredAlertCannotBeProvenCurrentAfterDateEdit() {
        var hidden = settings
        hidden.hideDetails = true
        let cheque = input(day: LocalDay(iso: "2026-10-04")!)
        let content = ReminderPlanner.chequeContent(cheque: cheque.snapshot, settings: hidden, offset: 0)
        var edited = cheque
        edited.snapshot.dueDate = cheque.snapshot.dueDate.adding(days: 1, calendar: calendar)
        XCTAssertFalse(ReminderRequestPolicy.isCurrentDelivered(identifier: "shekati.cheque.\(cheque.snapshot.id.uuidString).0",
                                                                 title: content.title, body: content.body, signature: nil,
                                                                 inputs: [edited], settings: hidden, hasCoverageNotice: false))
    }

    func testDeliveredSummaryRetainsOnlyWhileCountsAndPrivacyAreStillCurrent() throws {
        var configuration = settings
        configuration.dailySummary = true
        let dueToday = input(day: LocalDay(date: now, calendar: calendar))
        let near = input(day: dueToday.snapshot.dueDate.adding(days: 2, calendar: calendar))
        let summary = try XCTUnwrap(ReminderPlanner.makeSummary(day: dueToday.snapshot.dueDate, date: now,
                                                                 inputs: [dueToday, near], settings: configuration, calendar: calendar))
        XCTAssertTrue(isCurrent(summary, signature: nil, inputs: [dueToday, near], settings: configuration))
        XCTAssertFalse(isCurrent(summary, signature: nil, inputs: [near], settings: configuration))
        configuration.dailySummary = false
        XCTAssertFalse(isCurrent(summary, signature: nil, inputs: [dueToday, near], settings: configuration))
        configuration.dailySummary = true
        configuration.hideDetails = true
        XCTAssertFalse(isCurrent(summary, signature: nil, inputs: [dueToday, near], settings: configuration))
    }

    private func input(day: LocalDay) -> ChequeReminderInput {
        ChequeReminderInput(snapshot: ChequeSnapshot(direction: .incoming, amountMinorUnits: 123_456,
                                                     currencyCode: "JOD", dueDate: day, number: "00001234",
                                                     party: "Private example party"), enabled: true, offsets: nil)
    }

    private func refreshKey(_ inputs: [ChequeReminderInput], settings configuration: ReminderSettings? = nil,
                            dayRevision: Int = 0, authorization: Int = 2) -> [[String]] {
        ReminderRequestPolicy.refreshKey(inputs: inputs, settings: configuration ?? settings,
                                         dayRevision: dayRevision, authorizationStatus: authorization)
    }

    private func item(input: ChequeReminderInput, fireDate: Date) -> PlannedReminder {
        let content = ReminderPlanner.chequeContent(cheque: input.snapshot, settings: settings, offset: 0)
        return PlannedReminder(id: "shekati.cheque.\(input.snapshot.id.uuidString).0", fireDate: fireDate,
                               title: content.title, body: content.body, chequeID: input.snapshot.id, kind: .cheque)
    }

    private func content(item: PlannedReminder, signature: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = ["kind": item.kind.rawValue]
        if let id = item.chequeID {
            content.categoryIdentifier = ReminderRequestPolicy.chequeCategory
            content.userInfo["chequeID"] = id.uuidString
            content.userInfo["signature"] = signature
        }
        return content
    }

    private func calendarRequest(item: PlannedReminder, signature: String?) -> UNNotificationRequest {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: item.id, content: content(item: item, signature: signature),
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    private func intervalRequest(item: PlannedReminder, signature: String?, fireDate: Date, repeats: Bool = false) -> UNNotificationRequest {
        UNNotificationRequest(identifier: item.id, content: content(item: item, signature: signature),
                              trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, fireDate.timeIntervalSinceNow), repeats: repeats))
    }

    private func isCurrent(_ item: PlannedReminder, signature: String?, inputs: [ChequeReminderInput], settings: ReminderSettings) -> Bool {
        ReminderRequestPolicy.isCurrentDelivered(identifier: item.id, title: item.title, body: item.body,
                                                 signature: signature, inputs: inputs, settings: settings,
                                                 hasCoverageNotice: false, calendar: calendar)
    }
}
