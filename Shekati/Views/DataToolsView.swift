import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ShekatiCore

struct ChequeTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .commaSeparatedText, .pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let value = configuration.file.regularFileContents else { throw ChequeTransferError.invalidFile }
        data = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct DataToolsView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        List {
            Section(app.tr("Backup")) {
                NavigationLink(app.tr("Create encrypted backup")) { BackupCreationView() }
                NavigationLink(app.tr("Restore backup")) { BackupRestoreView() }
                Text(app.tr("A password-protected file includes every cheque, photo, reminder choice and deleted record. Keep the password safe; it cannot be recovered."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(app.tr("Excel and CSV")) {
                NavigationLink(app.tr("Import and export CSV")) { CSVTransferView() }
                Text(app.tr("CSV contains cheque details without photos. It can be opened in Excel. Review the file before importing."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(app.tr("Data and backup"))
    }
}

@MainActor
private struct BackupCreationView: View {
    @Environment(AppState.self) private var app
    @Query private var records: [ChequeRecord]
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var exporting = false
    @State private var document = ChequeTransferDocument(data: Data())
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(app.tr("Saved cheques"), value: records.count.formatted())
                LabeledContent(app.tr("Currency"), value: app.currencyCode)
                SecureField(app.tr("Backup password"), text: $password).textContentType(.newPassword)
                    .disabled(busy)
                    .accessibilityIdentifier("backupPassword")
                SecureField(app.tr("Confirm password"), text: $confirmation).textContentType(.newPassword)
                    .disabled(busy)
                    .accessibilityIdentifier("backupPasswordConfirmation")
            } footer: { Text(app.tr("Use at least 10 characters. Your password is not saved or sent anywhere.")) }
            Section {
                Button(app.tr("Save encrypted backup")) { createBackup() }
                    .disabled(busy || password.count < 10 || password != confirmation || app.currencyCode.isEmpty)
                    .accessibilityIdentifier("saveEncryptedBackup")
                if busy { ProgressView(app.tr("Preparing file")) }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
        }.navigationTitle(app.tr("Create encrypted backup"))
        .fileExporter(isPresented: $exporting, document: document, contentType: .data,
                      defaultFilename: "Shekati-\(LocalDay.today.iso).shekati") { result in
            switch result {
            case .success: message = app.tr("Backup saved. Keep the file and password in a safe place.")
            case .failure: errorMessage = app.tr("The file could not be saved. Please try again.")
            }
        }
        .alert(app.tr("Could not complete operation"), isPresented: errorBinding) {
            Button(app.tr("OK"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private var errorBinding: Binding<Bool> { Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }) }
    private func createBackup() {
        let payload = ChequeBackupPayload(currencyCode: app.currencyCode, records: records.map { ChequeBackupEntry(record: $0) },
                                         globalReminders: GlobalReminderBackup(preferences: app.preferences))
        let chosenPassword = password
        busy = true; message = nil
        Task {
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try EncryptedBackup.encrypt(payload, password: chosenPassword)
                }.value
                document = ChequeTransferDocument(data: bytes)
                password = ""; confirmation = ""; exporting = true
            } catch { errorMessage = transferMessage(error, app: app) }
            busy = false
        }
    }
}

@MainActor
private struct BackupRestoreView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var records: [ChequeRecord]
    @State private var importing = false
    @State private var filename = ""
    @State private var encryptedData: Data?
    @State private var password = ""
    @State private var payload: ChequeBackupPayload?
    @State private var preview: BackupRestorePreview?
    @State private var replaceExisting = false
    @State private var restoreReminderPreferences = false
    @State private var busy = false
    @State private var confirmation = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button(app.tr("Choose backup file")) { importing = true }.disabled(busy)
                if !filename.isEmpty { Text(filename).font(.footnote).lineLimit(2) }
                SecureField(app.tr("Backup password"), text: $password).disabled(busy)
                Button(app.tr("Review backup")) { review() }
                    .disabled(encryptedData == nil || password.isEmpty || busy)
                if busy { ProgressView(app.tr("Opening backup")) }
            }
            if let preview, let payload {
                Section(app.tr("Restore preview")) {
                    LabeledContent(app.tr("Currency"), value: payload.currencyCode)
                    LabeledContent(app.tr("New cheques"), value: preview.newCount.formatted())
                    LabeledContent(app.tr("Unchanged cheques"), value: preview.identicalCount.formatted())
                    LabeledContent(app.tr("Existing cheques with changes"), value: preview.changedCount.formatted())
                    LabeledContent(app.tr("Deleted records in backup"), value: preview.recentlyDeletedCount.formatted())
                    if preview.changedCount > 0 {
                        Toggle(app.tr("Replace matching existing cheques"), isOn: $replaceExisting)
                        Text(app.tr("Off by default. New cheques are added; existing cheques remain unchanged. Turn on only to replace matching records with this backup's contents."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if payload.globalReminders != nil {
                        Toggle(app.tr("Restore reminder preferences"), isOn: $restoreReminderPreferences)
                        Text(app.tr("This restores the default timing, daily summary and hidden notification details. Language and app lock stay as you set them on this iPhone."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(app.tr("Restore reviewed backup")) { confirmation = true }
                        .disabled(busy || (preview.newCount == 0 && (!replaceExisting || preview.changedCount == 0) && !restoreReminderPreferences))
                }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }.navigationTitle(app.tr("Restore backup"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get()
                encryptedData = try readTransferFile(url, maximumBytes: 256_000_000)
                filename = url.lastPathComponent; payload = nil; preview = nil; message = nil; replaceExisting = false
                restoreReminderPreferences = false
            } catch { errorMessage = transferMessage(error, app: app) }
        }
        .confirmationDialog(app.tr("Restore this backup?"), isPresented: $confirmation, titleVisibility: .visible) {
            Button(app.tr("Restore")) { restore() }
            Button(app.tr("Cancel"), role: .cancel) {}
        } message: { Text(app.tr("Review the counts and replacement choice. These changes will also sync to iCloud.")) }
        .alert(app.tr("Could not complete operation"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(app.tr("OK"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }

    private func review() {
        guard let encryptedData else { return }
        let enteredPassword = password
        busy = true; payload = nil; preview = nil; message = nil
        Task {
            do {
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try EncryptedBackup.decrypt(encryptedData, password: enteredPassword)
                }.value
                preview = try ChequeTransferService.preview(decoded, existing: records)
                payload = decoded; password = ""
                restoreReminderPreferences = records.isEmpty && decoded.globalReminders != nil
            } catch { errorMessage = transferMessage(error, app: app) }
            busy = false
        }
    }
    private func restore() {
        guard let payload else { return }
        do {
            let count = try ChequeTransferService.restore(payload, into: context, replaceExisting: replaceExisting)
            if restoreReminderPreferences { payload.globalReminders?.apply(to: app.preferences) }
            app.currencyCode = payload.currencyCode; app.didMutate()
            Task { await app.requestNotificationPermissionIfNeeded() }
            message = app.tr("Backup restored") + ": " + count.formatted()
            self.payload = nil; preview = nil; encryptedData = nil; password = ""
        } catch { errorMessage = transferMessage(error, app: app) }
    }
}

@MainActor
private struct CSVTransferView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var records: [ChequeRecord]
    @State private var importing = false
    @State private var exporting = false
    @State private var document = ChequeTransferDocument(data: Data())
    @State private var filename = "Shekati.csv"
    @State private var preview: CSVImportPreview?
    @State private var includeDuplicates = false
    @State private var confirmation = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var loading = false
    private var active: [ChequeSnapshot] { records.filter(\.isActive).map(\.snapshot) }
    private var selectedCount: Int { preview?.rows.filter { includeDuplicates || !$0.isProbableDuplicate }.count ?? 0 }

    var body: some View {
        List {
            Section(app.tr("Export")) {
                Button(app.tr("Export saved cheques to CSV")) {
                    document = ChequeTransferDocument(data: ChequeCSV.export(active))
                    filename = "Shekati-\(LocalDay.today.iso).csv"; exporting = true
                }.disabled(active.isEmpty)
                Text(app.tr("Exported files contain readable cheque details. Share only with people you choose."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(app.tr("Import")) {
                Button(app.tr("Download CSV template")) {
                    document = ChequeTransferDocument(data: ChequeCSV.template(currencyCode: app.currencyCode))
                    filename = "Shekati-template.csv"; exporting = true
                }
                Button(app.tr("Choose CSV file")) { importing = true }.disabled(loading)
                if loading { ProgressView(app.tr("Reviewing CSV")) }
                Text(app.tr("Use the template's English column names, YYYY-MM-DD dates and your selected currency. Keep cheque numbers as text in Excel to preserve leading zeros."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let preview {
                Section(app.tr("Import preview")) {
                    LabeledContent(app.tr("Valid rows"), value: preview.rows.count.formatted())
                    LabeledContent(app.tr("Rows with errors"), value: preview.issues.count.formatted())
                    LabeledContent(app.tr("Possible duplicates"), value: preview.duplicateCount.formatted())
                    if preview.duplicateCount > 0 { Toggle(app.tr("Include possible duplicates"), isOn: $includeDuplicates) }
                    Button(app.tr("Import reviewed rows") + " (\(selectedCount))") { confirmation = true }
                        .disabled(selectedCount == 0 || loading)
                    Text(app.tr("Rows with errors are excluded. Possible duplicates are excluded unless you choose to include them. No cheque is saved before confirmation."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(app.tr("Rows")) {
                    ForEach(Array(preview.rows.prefix(200))) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(row.line). \(row.snapshot.party.isEmpty ? row.snapshot.number : row.snapshot.party)")
                            Text(row.snapshot.number + " · " + app.formatAmount(row.snapshot.amountMinorUnits) + " · " + row.snapshot.dueDate.iso)
                                .font(.caption).foregroundStyle(.secondary)
                            if row.isProbableDuplicate { Text(app.tr("Possible duplicate")).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    if preview.rows.count > 200 { Text(app.tr("Showing the first 200 rows. The counts include every row.")) }
                }
                if !preview.issues.isEmpty {
                    Section(app.tr("Rows with errors")) {
                        ForEach(Array(preview.issues.prefix(200))) { issue in
                            Text("\(issue.line): " + app.tr(issue.message)).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }.navigationTitle(app.tr("Excel and CSV"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            switch result {
            case .success(let url): reviewCSV(url)
            case .failure(let error): errorMessage = transferMessage(error, app: app)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText,
                      defaultFilename: filename) { result in
            if case .failure = result { errorMessage = app.tr("The file could not be saved. Please try again.") }
        }
        .confirmationDialog(app.tr("Import these cheques?"), isPresented: $confirmation, titleVisibility: .visible) {
            Button(app.tr("Import")) { saveImport() }
            Button(app.tr("Cancel"), role: .cancel) {}
        } message: { Text(app.tr("Only the reviewed valid rows will be added. These changes will also sync to iCloud.")) }
        .alert(app.tr("Could not complete operation"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(app.tr("OK"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }
    private func reviewCSV(_ url: URL) {
        guard !loading else { return }
        let current = active
        let code = app.currencyCode
        loading = true; preview = nil; message = nil
        Task {
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    let bytes = try readTransferFile(url, maximumBytes: 10_000_000)
                    return try ChequeCSV.preview(bytes, currencyCode: code, existing: current)
                }.value
                includeDuplicates = false
            } catch { errorMessage = transferMessage(error, app: app) }
            loading = false
        }
    }
    private func saveImport() {
        guard !loading, let preview else { return }
        do {
            let payload = preview.payload(includeDuplicates: includeDuplicates)
            // Recheck against the live store, because iCloud may have imported duplicates since preview.
            let current = try context.fetch(FetchDescriptor<ChequeRecord>()).filter(\.isActive).map(\.snapshot)
            let nowDuplicates = includeDuplicates ? Set<UUID>() : ChequeCSV.duplicateIDs(for: payload.records.map(\.snapshot), existing: current)
            if !nowDuplicates.isEmpty {
                self.preview = CSVImportPreview(rows: preview.rows.map { row in
                    var updated = row
                    updated.isProbableDuplicate = row.isProbableDuplicate || nowDuplicates.contains(row.snapshot.id)
                    return updated
                }, issues: preview.issues, currencyCode: preview.currencyCode)
                errorMessage = app.tr("Your records changed. Review the updated duplicate warnings before importing.")
                return
            }
            let count = try ChequeTransferService.restore(payload, into: context)
            app.didMutate(); self.preview = nil
            Task { await app.requestNotificationPermissionIfNeeded() }
            message = app.tr("Cheques imported") + ": " + count.formatted()
        } catch { errorMessage = transferMessage(error, app: app) }
    }
}

private func readTransferFile(_ url: URL, maximumBytes: Int) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maximumBytes else { throw ChequeTransferError.invalidFile }
    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
    guard bytes.count <= maximumBytes else { throw ChequeTransferError.invalidFile }
    return bytes
}

@MainActor private func transferMessage(_ error: Error, app: AppState) -> String {
    guard let ownError = error as? ChequeTransferError else { return app.tr("The file could not be read or saved. Please try again.") }
    return app.tr(ownError.errorDescription ?? "Could not complete operation")
}
