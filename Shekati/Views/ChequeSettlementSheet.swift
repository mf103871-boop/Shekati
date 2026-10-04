import SwiftUI
import SwiftData
import ShekatiCore

/// Shared by the list and detail screens; settling always needs an actual civil date.
@MainActor
struct ChequeSettlementSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: ChequeRecord
    @State private var actualDate: Date
    @State private var errorMessage: String?

    init(record: ChequeRecord) {
        self.record = record
        _actualDate = State(initialValue: (record.actualDate ?? .today).date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(app.tr(record.direction == .incoming ? "Collection date" : "Payment date"),
                               selection: $actualDate, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("actualSettlementDate")
                    Text(app.formatDay(LocalDay(date: actualDate)))
                        .font(.footnote).foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                } footer: {
                    Text(app.tr("Choose the date the cheque actually cleared."))
                }
            }
            .environment(\.locale, app.preferences.language.locale)
            .environment(\.layoutDirection, direction)
            .navigationTitle(app.tr(record.direction == .incoming ? "Mark collected" : "Mark paid"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(app.tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(app.tr("Save")) { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("confirmSettlement")
                }
            }
        }
        .environment(\.locale, app.preferences.language.locale)
        .environment(\.layoutDirection, direction)
        .presentationDetents([.medium, .large])
        .alert(app.tr("Could not save changes"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(app.tr("OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var direction: LayoutDirection {
        app.preferences.language == .arabic ? .rightToLeft : .leftToRight
    }

    private func save() {
        guard record.deletedAt == nil else {
            errorMessage = app.tr("Restore this cheque before changing it.")
            return
        }
        let day = LocalDay(date: actualDate)
        guard day <= .today else {
            errorMessage = app.tr("The actual payment or collection date cannot be in the future.")
            return
        }
        guard record.issueDate.map({ day >= $0 }) ?? true else {
            errorMessage = app.tr("The actual payment or collection date cannot be before the issue date.")
            return
        }
        record.status = .settled
        record.actualDate = day
        do {
            try context.save()
            app.didMutate()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = app.tr("Your previous details were kept. Please try again.")
        }
    }
}
