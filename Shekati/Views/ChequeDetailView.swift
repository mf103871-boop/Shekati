import SwiftUI
import SwiftData
import UIKit
import ShekatiCore

@MainActor
struct ChequeDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: ChequeRecord
    /// Confirms the record still exists. This view can remain on another tab's navigation stack
    /// after Recently Deleted (or another device) removes it, and a deleted model must not be read.
    /// The match is by instance identity, so a duplicate id surviving elsewhere cannot mask this deletion.
    @Query private var liveRecords: [ChequeRecord]
    @State private var showingEditor = false
    @State private var showingStatus = false
    @State private var showingSettlement = false
    @State private var showingDelete = false
    @State private var errorMessage: String?
    @State private var preview: ChequeImagePreview?

    init(record: ChequeRecord) {
        self.record = record
        let id = record.id
        _liveRecords = Query(filter: #Predicate<ChequeRecord> { $0.id == id })
    }

    var body: some View {
        Group {
            if !liveRecords.contains(where: { $0 === record || $0.persistentModelID == record.persistentModelID }) {
                removedCheque
            }
            else if record.deletedAt != nil { deletedCheque } else { activeDetail }
        }
        .alert(app.tr("Could not save changes"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(app.tr("OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var activeDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(app.tr(record.direction == .incoming ? "Incoming cheque" : "Outgoing cheque"),
                              systemImage: record.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                        Spacer()
                        StatusPill(snapshot: record.snapshot)
                    }
                    Text(CurrencyMath.format(minorUnits: record.amountMinorUnits, currencyCode: record.currencyCode,
                                             locale: app.preferences.language.locale))
                        .font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(record.direction == .incoming ? Theme.accent : Theme.navy)
                    if !record.party.isEmpty { Text(NumericInput.latinDigits(record.party)).font(.title3.weight(.medium)) }
                    Divider()
                    LabeledContent(app.tr("Due date"), value: app.formatDay(record.dueDate))
                        .foregroundStyle(record.snapshot.isOverdue(on: app.today) ? Theme.red : Theme.navy)
                    if record.snapshot.isOutstanding {
                        Text(app.relativeDueDate(record.dueDate))
                            .font(.subheadline).foregroundStyle(record.snapshot.isOverdue(on: app.today) ? Theme.red : .secondary)
                        Button { showingSettlement = true } label: {
                            Label(app.tr(record.direction == .incoming ? "Mark collected" : "Mark paid"), systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("primarySettlement")
                    }
                    if let actual = record.actualDate {
                        LabeledContent(app.tr(record.direction == .incoming ? "Collection date" : "Payment date"),
                                       value: app.formatDay(actual))
                    }
                    if let issue = record.issueDate {
                        LabeledContent(app.tr("Issue date"), value: app.formatDay(issue))
                    }
                }
                .padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 15) {
                    Text(app.tr("Cheque details")).font(.headline)
                    detailLine("Cheque number", record.number)
                    detailLine("Bank", record.bank)
                    if !record.branch.isEmpty { detailLine("Branch", record.branch) }
                    detailLine(record.direction == .incoming ? "Payer" : "Payee", record.party)
                    if !record.accountReference.isEmpty { detailLine("Account reference", record.accountReference) }
                    LabeledContent(app.tr("Date added"), value: app.formatDay(LocalDay(date: record.createdAt)))
                        .font(.subheadline)
                    if !record.notes.isEmpty {
                        Divider()
                        Text(app.tr("Notes")).font(.subheadline.weight(.medium))
                        Text(NumericInput.latinDigits(record.notes)).font(.subheadline).textSelection(.enabled)
                    }
                }
                .padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Label(app.tr("Reminders"), systemImage: "bell.badge").font(.headline)
                    Text(app.tr(record.remindersEnabled ? "Reminders enabled" : "Reminders disabled"))
                        .font(.subheadline)
                    if record.remindersEnabled {
                        reminderCoverage
                        if record.reminderOffsets == nil {
                            Text(app.tr("Uses default reminders"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let effectiveOffsets = record.reminderOffsets ?? app.preferences.reminderOffsets
                        Text(effectiveOffsets.isEmpty ? app.tr("No reminder days selected") :
                             effectiveOffsets.sorted(by: >).map(reminderTitle).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent(app.tr("Reminder time"), value: reminderClock)
                            .font(.subheadline)
                        if record.reminderOffsets != nil && (record.reminderHour == nil || record.reminderMinute == nil) {
                            Text(app.tr("Uses default reminder time"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !record.snapshot.isOutstanding {
                            Text(app.tr("Reminders stop when a cheque is settled or cancelled."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))

                if record.frontImageData != nil || record.backImageData != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(app.tr("Cheque images")).font(.headline)
                        if let data = record.frontImageData { imageButton(data, title: "Front") }
                        if let data = record.backImageData { imageButton(data, title: "Back") }
                    }
                    .padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                }

                Button { showingStatus = true } label: {
                    Label(app.tr("Change status"), systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) { showingDelete = true } label: {
                    Label(app.tr("Delete cheque"), systemImage: "trash")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
            }
            .padding(18)
        }
        .background(Theme.background)
        .navigationTitle(app.tr("Cheque"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(app.tr("Edit")) { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                ChequeEditorView(record: record)
                    .environment(\.locale, app.preferences.language.locale)
                    .environment(\.layoutDirection, sheetDirection)
            }
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, sheetDirection)
        }
        .sheet(isPresented: $showingSettlement) { ChequeSettlementSheet(record: record) }
        .sheet(item: $preview) { item in
            NavigationStack {
                ScrollView {
                    Image(uiImage: item.image).resizable().scaledToFit().padding()
                }
                .background(Theme.background)
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, sheetDirection)
                .navigationTitle(app.tr(item.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(app.tr("Done")) { preview = nil }
                    }
                }
            }
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, sheetDirection)
        }
        .confirmationDialog(app.tr("Change status"), isPresented: $showingStatus, titleVisibility: .visible) {
            Button(app.tr(record.direction == .incoming ? "Mark collected" : "Mark paid")) {
                showingSettlement = true
            }
            Button(app.tr("Mark pending")) { transition(to: .pending) }
            Button(app.tr("Mark returned")) { transition(to: .returned) }
            Button(app.tr("Mark cancelled"), role: .destructive) { transition(to: .cancelled) }
            Button(app.tr("Cancel"), role: .cancel) { }
        }
        .alert(app.tr("Delete this cheque?"), isPresented: $showingDelete) {
            Button(app.tr("Delete"), role: .destructive) { deleteRecord() }
            Button(app.tr("Cancel"), role: .cancel) { }
        } message: {
            Text(app.tr("The cheque moves to Recently Deleted for 30 days. Its reminders stop; you can restore its details and photos."))
        }
    }

    private var sheetDirection: LayoutDirection {
        app.preferences.language == .arabic ? .rightToLeft : .leftToRight
    }

    @ViewBuilder
    private var reminderCoverage: some View {
        if record.snapshot.isOutstanding {
            if app.notifications.isDenied {
                Text(app.tr("Notifications are off")).font(.subheadline).foregroundStyle(.orange)
                NavigationLink(app.tr("Open reminder settings")) { SettingsView() }
            } else if let next = app.notifications.nextReminderDate(for: record.id) {
                LabeledContent(app.tr("Next scheduled reminder"), value: app.formatTimestamp(next))
                    .font(.subheadline).accessibilityIdentifier("nextScheduledReminder")
            } else if (record.reminderOffsets ?? app.preferences.reminderOffsets).isEmpty {
                Text(app.tr(app.preferences.dailySummary ? "Daily summary is enabled; no individual reminder days are selected." : "No reminder days selected"))
                    .font(.subheadline).foregroundStyle(.orange)
                NavigationLink(app.tr("Open reminder settings")) { SettingsView() }
            } else if !hasFutureReminderTime {
                Text(app.tr("All individual reminder times for this cheque have passed."))
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink(app.tr("Open reminder settings")) { SettingsView() }
            } else {
                Text(app.tr("No upcoming reminder is currently scheduled for this cheque."))
                    .font(.subheadline).foregroundStyle(.orange)
                NavigationLink(app.tr("Open reminder settings")) { SettingsView() }
            }
        }
    }

    private var hasFutureReminderTime: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let hour = record.reminderHour ?? app.preferences.reminderHour
        let minute = record.reminderMinute ?? app.preferences.reminderMinute
        return (record.reminderOffsets ?? app.preferences.reminderOffsets).contains { offset in
            guard (0...365).contains(offset) else { return false }
            var parts = calendar.dateComponents([.year, .month, .day], from: record.dueDate.adding(days: -offset).date(calendar: calendar))
            parts.hour = hour; parts.minute = minute
            return calendar.date(from: parts).map { $0 > now } ?? false
        }
    }

    private var deletedCheque: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash").font(.largeTitle).foregroundStyle(.secondary)
            Text(app.tr("Cheque moved to Recently Deleted")).font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(app.tr("You can restore its details and photos for 30 days."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(app.tr("Undo deletion")) { restoreRecord() }
                .buttonStyle(.borderedProminent)
                .disabled(!record.canRestore(asOf: Date()))
                .accessibilityIdentifier("undoChequeDeletion")
            Button(app.tr("Done")) { dismiss() }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        .background(Theme.background)
        .navigationTitle(app.tr("Recently Deleted"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var removedCheque: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text(app.tr("This cheque is no longer available")).font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(app.tr("It was permanently deleted, possibly from another device."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(app.tr("Done")) { dismiss() }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        .background(Theme.background)
        .navigationTitle(app.tr("Cheque"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value.isEmpty ? app.tr("Not provided") : NumericInput.latinDigits(value))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        } label: { Text(app.tr(title)) }
        .font(.subheadline)
    }

    @ViewBuilder private func imageButton(_ data: Data, title: String) -> some View {
        if let image = UIImage(data: data) {
            Button { preview = ChequeImagePreview(image: image, title: title) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.tr(title)).font(.subheadline.weight(.medium))
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.tr(title) + " " + app.tr("Cheque image"))
        }
    }

    private func reminderTitle(_ offset: Int) -> String {
        if offset == 0 { return app.tr("On due date") }
        if offset == 1 { return app.tr("1 day before") }
        if offset == 3 { return app.tr("3 days before") }
        return Localization.daysBefore(offset, language: app.preferences.language)
    }

    private var reminderClock: String {
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = record.reminderHour ?? app.preferences.reminderHour
        components.minute = record.reminderMinute ?? app.preferences.reminderMinute
        let date = calendar.date(from: components) ?? Date()
        return NumericInput.latinDigits(date.formatted(.dateTime.hour().minute().locale(app.preferences.language.locale)))
    }

    @discardableResult
    private func transition(to status: ChequeStatus, actualDate: LocalDay? = nil) -> Bool {
        guard record.deletedAt == nil else { return false }
        record.status = status
        record.actualDate = status == .settled ? actualDate : nil
        do {
            try context.save()
            app.didMutate()
            return true
        } catch {
            context.rollback()
            errorMessage = app.tr("Your previous details were kept. Please try again.")
            return false
        }
    }

    private func deleteRecord() {
        record.deletedAt = Date()
        do {
            try context.save()
            app.didMutate()
        } catch {
            context.rollback()
            errorMessage = app.tr("The cheque could not be deleted. Please try again.")
        }
    }

    private func restoreRecord() {
        guard record.canRestore(asOf: Date()) else { return }
        record.deletedAt = nil
        do {
            try context.save()
            app.didMutate()
        } catch {
            context.rollback()
            errorMessage = app.tr("The cheque could not be restored. Please try again.")
        }
    }
}

private struct ChequeImagePreview: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}
