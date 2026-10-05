import SwiftUI
import SwiftData

@MainActor
struct TrashView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ChequeRecord> { $0.deletedAt != nil },
           sort: \ChequeRecord.deletedAt, order: .reverse) private var deleted: [ChequeRecord]
    @State private var deleting: ChequeRecord?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text(app.tr("Restore deleted cheques within 30 days. After that, only permanent deletion is available."))
                    .font(.footnote).foregroundStyle(.secondary)
                Text(app.tr("Permanent deletion also syncs to iCloud. Keep an independent backup if needed."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if deleted.isEmpty {
                ContentUnavailableView(app.tr("No deleted cheques"), systemImage: "trash")
            }
            ForEach(deleted) { record in
                VStack(alignment: .leading, spacing: 10) {
                    ChequeRowView(record: record)
                    if let date = record.deletedAt {
                        Text(app.tr("Deleted") + ": " + app.formatTimestamp(date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(app.tr("Restore")) { restore(record) }
                            .buttonStyle(.bordered).disabled(!record.canRestore())
                            .accessibilityIdentifier("restore-\(record.id.uuidString)")
                        Spacer()
                        Button(app.tr("Delete permanently"), role: .destructive) { deleting = record }
                            .buttonStyle(.bordered)
                    }
                    if !record.canRestore() {
                        Text(app.tr("The 30-day restore period has ended."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
        }
        .navigationTitle(app.tr("Recently deleted"))
        .confirmationDialog(app.tr("Delete permanently?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(app.tr("Delete permanently"), role: .destructive) { permanentlyDelete() }
                Button(app.tr("Cancel"), role: .cancel) { deleting = nil }
            } message: { Text(app.tr("This removes the cheque and its photos from this iPhone and iCloud. It cannot be undone.")) }
        .alert(app.tr("Could not save changes."), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(app.tr("OK"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }

    private func restore(_ record: ChequeRecord) {
        guard record.canRestore() else { return }
        record.deletedAt = nil
        do { try context.save(); app.didMutate() }
        catch { context.rollback(); errorMessage = app.tr("Your change was not saved. Please try again.") }
    }
    private func permanentlyDelete() {
        guard let record = deleting else { return }
        context.delete(record)
        do { try context.save(); deleting = nil; app.didMutate() }
        catch { context.rollback(); deleting = nil; errorMessage = app.tr("Your change was not saved. Please try again.") }
    }
}
