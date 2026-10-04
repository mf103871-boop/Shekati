import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation
import UserNotifications
import ShekatiCore

@MainActor
struct ChequeEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ChequeRecord]
    let record: ChequeRecord?

    @State private var direction: ChequeDirection
    @State private var amountText: String
    @State private var dueDate: Date
    @State private var includeIssueDate: Bool
    @State private var issueDate: Date
    @State private var number: String
    @State private var bank: String
    @State private var branch: String
    @State private var party: String
    @State private var accountReference: String
    @State private var notes: String
    @State private var frontImageData: Data?
    @State private var backImageData: Data?
    @State private var remindersEnabled: Bool
    @State private var useDefaultReminders: Bool
    @State private var before3: Bool
    @State private var before1: Bool
    @State private var onDueDate: Bool
    @State private var customOffsets: Set<Int>
    @State private var reminderTime: Date?
    @State private var customDays = ""
    @State private var frontPhoto: PhotosPickerItem?
    @State private var backPhoto: PhotosPickerItem?
    @State private var showingScanner = false
    @State private var scanSide: AttachmentSide = .front
    @State private var showingCameraHelp = false
    @State private var ocrSuggestion: OCRSuggestion?
    @State private var isReadingImage = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var cleanFormSignature: [String]?
    @State private var showingDiscard = false
    @State private var extraDetailsExpanded: Bool
    @State private var imagesExpanded: Bool
    @State private var reminderOptionsExpanded: Bool
    @State private var keepEntryDetails = false
    @State private var dueDateNeedsReview = false
    @State private var amountError: String?
    @State private var dateError: String?
    @State private var savedNotice = false
    @State private var entrySequence = 0
    @State private var showingDuplicate = false
    @State private var duplicateIDs: [UUID] = []
    @State private var pendingAddAnother = false
    @State private var duplicatePreview: ChequeRecord?
    @FocusState private var focusedField: EntryField?

    private enum EntryField: Hashable { case amount, party, number, bank }

    init(record: ChequeRecord? = nil) {
        self.record = record
        let offsets = record?.reminderOffsets ?? [3, 1, 0]
        _direction = State(initialValue: record?.direction ?? .incoming)
        _amountText = State(initialValue: record.map {
            CurrencyMath.editable(minorUnits: $0.amountMinorUnits, currencyCode: $0.currencyCode)
        } ?? "")
        _dueDate = State(initialValue: record?.dueDate.date() ?? Date())
        _includeIssueDate = State(initialValue: record?.issueDate != nil)
        _issueDate = State(initialValue: record?.issueDate?.date() ?? Date())
        _number = State(initialValue: record?.number ?? "")
        _bank = State(initialValue: record?.bank ?? "")
        _branch = State(initialValue: record?.branch ?? "")
        _party = State(initialValue: record?.party ?? "")
        _accountReference = State(initialValue: record?.accountReference ?? "")
        _notes = State(initialValue: record?.notes ?? "")
        _frontImageData = State(initialValue: record?.frontImageData)
        _backImageData = State(initialValue: record?.backImageData)
        _remindersEnabled = State(initialValue: record?.remindersEnabled ?? true)
        _useDefaultReminders = State(initialValue: record?.reminderOffsets == nil)
        _before3 = State(initialValue: offsets.contains(3))
        _before1 = State(initialValue: offsets.contains(1))
        _onDueDate = State(initialValue: offsets.contains(0))
        _customOffsets = State(initialValue: Set(offsets.filter { ![0, 1, 3].contains($0) }))
        _extraDetailsExpanded = State(initialValue: record.map {
            $0.issueDate != nil || [$0.bank, $0.branch, $0.accountReference, $0.notes].contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        } ?? false)
        _imagesExpanded = State(initialValue: record?.frontImageData != nil || record?.backImageData != nil)
        _reminderOptionsExpanded = State(initialValue: record?.reminderOffsets != nil ||
                                        record?.reminderHour != nil || record?.reminderMinute != nil)
        if let hour = record?.reminderHour, let minute = record?.reminderMinute {
            _reminderTime = State(initialValue: Self.clockDate(hour: hour, minute: minute))
        } else {
            _reminderTime = State(initialValue: nil)
        }
    }

    private var currency: String { record?.currencyCode ?? app.currencyCode }
    private var busy: Bool { isSaving || isReadingImage }
    private var effectiveReminderTime: Date {
        reminderTime ?? Self.clockDate(hour: app.preferences.reminderHour, minute: app.preferences.reminderMinute)
    }
    private var selectedOffsets: [Int] {
        var offsets = customOffsets
        if before3 { offsets.insert(3) }
        if before1 { offsets.insert(1) }
        if onDueDate { offsets.insert(0) }
        return offsets.sorted(by: >)
    }

    private var formSignature: [String] {
        [direction.rawValue, amountText, LocalDay(date: dueDate).iso,
         String(includeIssueDate), LocalDay(date: issueDate).iso,
         number, bank, branch, party, accountReference, notes,
         String(remindersEnabled), String(useDefaultReminders),
         selectedOffsets.map(String.init).joined(separator: ","),
         reminderTime.map { String($0.timeIntervalSince1970) } ?? "defaultTime",
         String(frontImageData?.hashValue ?? 0), String(backImageData?.hashValue ?? 0)]
    }

    private var hasEdited: Bool {
        guard let cleanFormSignature else { return false }
        return formSignature != cleanFormSignature
    }

    var body: some View {
        Form {
            essentialFields

            Section {
                DisclosureGroup(isExpanded: $extraDetailsExpanded) {
                    TextField(app.tr("Bank (optional)"), text: $bank)
                        .focused($focusedField, equals: .bank)
                        .submitLabel(.done).onSubmit { focusedField = nil }
                        .accessibilityIdentifier("bankField")
                    if focusedField == .bank { previousSuggestions(for: .bank) }
                    TextField(app.tr("Branch (optional)"), text: $branch)
                    TextField(app.tr("Account reference (optional)"), text: $accountReference)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle(app.tr("Add issue date"), isOn: $includeIssueDate)
                    if includeIssueDate {
                        DatePicker(app.tr("Issue date"), selection: $issueDate, displayedComponents: .date)
                    }
                    TextField(app.tr("Notes (optional)"), text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } label: {
                    Text(app.tr("More details")).accessibilityIdentifier("extraChequeDetails")
                }
            }

            Section {
                DisclosureGroup(isExpanded: $imagesExpanded) {
                    attachment(.front, data: frontImageData, selection: $frontPhoto)
                    attachment(.back, data: backImageData, selection: $backPhoto)
                    if frontImageData != nil {
                        Button {
                            Task { await recognizeFrontImage() }
                        } label: {
                            HStack {
                                Label(app.tr("Read details from front image"), systemImage: "text.viewfinder")
                                Spacer()
                                if isReadingImage { ProgressView() }
                            }
                        }
                        .disabled(busy)
                    }
                } label: {
                    Label(app.tr("Scan or add photos"), systemImage: "camera")
                        .accessibilityIdentifier("chequeImageOptions")
                }
            } header: {
                Text(app.tr("Cheque images"))
            } footer: {
                Text(app.tr("Scan or choose an image, review the suggested details, then save the cheque."))
            }

            Section {
                Toggle(app.tr("Reminders enabled"), isOn: $remindersEnabled)
                if remindersEnabled {
                    DisclosureGroup(isExpanded: $reminderOptionsExpanded) {
                        Toggle(app.tr("Use default reminders"), isOn: $useDefaultReminders)
                        if useDefaultReminders {
                            Text(app.tr("The reminder days and time from Settings will be used."))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(app.preferences.reminderOffsets.isEmpty ? app.tr("No reminder days selected") :
                                 app.preferences.reminderOffsets.sorted(by: >).map(reminderTitle).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            DatePicker(app.tr("Reminder time"), selection: Binding(
                                get: { effectiveReminderTime }, set: { reminderTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            Toggle(app.tr("3 days before"), isOn: $before3)
                            Toggle(app.tr("1 day before"), isOn: $before1)
                            Toggle(app.tr("On due date"), isOn: $onDueDate)
                            ForEach(customOffsets.sorted(by: >), id: \.self) { offset in
                                HStack {
                                    Text(String(offset) + " " + app.tr("days before"))
                                    Spacer()
                                    Button(role: .destructive) { customOffsets.remove(offset) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(app.tr("Remove reminder") + " " + String(offset))
                                }
                            }
                            HStack {
                                TextField(app.tr("Days before (1–365)"), text: $customDays)
                                    .keyboardType(.numberPad)
                                Button(app.tr("Add")) { addCustomReminder() }
                                    .buttonStyle(.borderless)
                            }
                        }
                    } label: {
                        Text(app.tr("Reminder options")).accessibilityIdentifier("chequeReminderOptions")
                    }
                }
            } header: {
                Text(app.tr("Reminders"))
            } footer: {
                Text(app.tr("Reminders stop when a cheque is settled or cancelled. Past reminder times are skipped."))
            }

            if record == nil {
                Section {
                    Toggle(app.tr("Keep type, bank and name for the next cheque"), isOn: $keepEntryDetails)
                        .accessibilityIdentifier("keepEntryDetails")
                } footer: {
                    Text(app.tr("The next cheque always needs its own amount, number, photos and a reviewed due date."))
                }
            }

        }
        // A new consecutive entry starts at the top instead of retaining the previous bank-row scroll.
        .id(app.preferences.language.rawValue + "-" + String(entrySequence))
        .safeAreaInset(edge: .top, spacing: 0) {
            if savedNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    Text(app.tr("Cheque saved. Enter the next cheque."))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("consecutiveChequeSaved")
                }
                .font(.subheadline).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.background)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(app.tr(record == nil ? "Add cheque" : "Edit cheque"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(app.tr("Cancel")) {
                    if hasEdited { showingDiscard = true } else { dismiss() }
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text(app.tr("Save")).fontWeight(.semibold) }
                }
                .disabled(busy)
                .accessibilityLabel(app.tr("Save cheque"))
                .accessibilityIdentifier("saveCheque")
            }
            if record == nil {
                ToolbarItem(placement: .bottomBar) {
                    Button(app.tr("Save and add another")) {
                        focusedField = nil
                        Task { await save(addAnother: true) }
                    }
                    .fontWeight(.semibold).disabled(busy)
                    .accessibilityIdentifier("saveAndAddAnother")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .amount {
                    Button(app.tr("Next")) { focusedField = .party }
                } else if focusedField == .party {
                    Button(app.tr("Next")) { focusedField = .number }
                }
                Spacer()
                Button(app.tr("Done")) { focusedField = nil }
            }
        }
        .interactiveDismissDisabled(hasEdited || busy)
        .onAppear {
            if cleanFormSignature == nil { cleanFormSignature = formSignature }
        }
        .onChange(of: amountText) { _, _ in amountError = nil }
        .onChange(of: frontPhoto) { _, item in
            Task { await loadPhoto(item, side: .front) }
        }
        .onChange(of: backPhoto) { _, item in
            Task { await loadPhoto(item, side: .back) }
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScanner(onScan: { image in
                storeImage(image, side: scanSide)
                showingScanner = false
            }, onCancel: { showingScanner = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { ocrSuggestion != nil }, set: { if !$0 { ocrSuggestion = nil } }
        )) {
            if let suggestion = ocrSuggestion {
                NavigationStack {
                    OCRReviewSheet(suggestion: suggestion) { selected in
                        applyOCR(suggestion, selected: selected)
                        ocrSuggestion = nil
                    }
                }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, app.preferences.language == .arabic ? .rightToLeft : .leftToRight)
            }
        }
        .sheet(item: $duplicatePreview) { existing in
            NavigationStack {
                ChequeDetailView(record: existing)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button(app.tr("Done")) { duplicatePreview = nil }
                            .accessibilityIdentifier("closeDuplicatePreview")
                    } }
            }
                .environment(\.locale, app.preferences.language.locale)
                .environment(\.layoutDirection, app.preferences.language == .arabic ? .rightToLeft : .leftToRight)
        }
        .alert(app.tr("Similar cheque found"), isPresented: $showingDuplicate) {
            Button(app.tr("View existing cheque")) {
                duplicatePreview = records.first { duplicateIDs.contains($0.id) && $0.deletedAt == nil }
            }
            Button(app.tr("Save anyway")) {
                Task { await save(addAnother: pendingAddAnother, allowDuplicate: true) }
            }
            Button(app.tr("Keep editing"), role: .cancel) { }
        } message: {
            Text(app.tr("A similar cheque is already saved. Review it before adding another."))
        }
        .alert(app.tr("Camera unavailable"), isPresented: $showingCameraHelp) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button(app.tr("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(app.tr("OK"), role: .cancel) { }
        } message: {
            Text(app.tr("You can choose an image from Photos or enter all cheque details manually. Allow camera access in Settings to scan."))
        }
        .alert(app.tr("Check the details"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(app.tr("OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert(app.tr("Discard changes?"), isPresented: $showingDiscard) {
            Button(app.tr("Discard"), role: .destructive) { dismiss() }
            Button(app.tr("Keep editing"), role: .cancel) { }
        } message: { Text(app.tr("Your unsaved changes will be lost.")) }
    }

    private var essentialFields: some View {
    Section {
        Picker(app.tr("Direction"), selection: $direction) {
            Text(app.tr("Incoming")).tag(ChequeDirection.incoming)
            Text(app.tr("Outgoing")).tag(ChequeDirection.outgoing)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("chequeDirectionPicker")
        HStack {
            Text(app.tr("Amount"))
            Spacer(minLength: 12)
            TextField(app.tr("Required"), text: $amountText)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .amount)
                .accessibilityLabel(app.tr("Amount"))
                .accessibilityIdentifier("amountField")
            Text(currency).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        if let amountError {
            Text(amountError).font(.footnote).foregroundStyle(Theme.red)
                .accessibilityIdentifier("amountValidationError")
        }
        DatePicker(app.tr("Due date"), selection: $dueDate, displayedComponents: .date)
            .accessibilityIdentifier("dueDateField")
            .onChange(of: dueDate) { _, _ in
                if !isResetting { dueDateNeedsReview = false; dateError = nil }
            }
        Text(app.formatDay(LocalDay(date: dueDate)) + " · " + app.relativeDueDate(LocalDay(date: dueDate)))
            .font(.footnote).foregroundStyle(.secondary)
        if dueDateNeedsReview {
            Button(app.tr("Confirm this due date")) { dueDateNeedsReview = false; dateError = nil }
                .accessibilityIdentifier("confirmNextChequeDate")
            Text(app.tr("Review the due date for the next cheque."))
                .font(.footnote).foregroundStyle(.orange)
        }
        if let dateError { Text(dateError).font(.footnote).foregroundStyle(Theme.red) }
        TextField(app.tr(direction == .incoming ? "Payer (optional)" : "Payee (optional)"), text: $party)
            .focused($focusedField, equals: .party)
            .submitLabel(.next).onSubmit { focusedField = .number }
            .accessibilityIdentifier("partyField")
        if focusedField == .party { previousSuggestions(for: .party) }
        TextField(app.tr("Cheque number (optional)"), text: $number)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focusedField, equals: .number)
            .submitLabel(.done).onSubmit { focusedField = nil }
            .accessibilityIdentifier("chequeNumberField")
    } header: {
        Text(app.tr("Cheque details"))
    } footer: {
        Text(app.tr("Enter a positive amount and the date written on the cheque."))
    }
    }

    @ViewBuilder
    private func previousSuggestions(for field: EntryField) -> some View {
        let active = records.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
        let values = field == .bank ? active.map(\.bank) : active.map(\.party)
        let query = field == .bank ? bank : party
        let choices = ChequeEntryAssistance.suggestions(from: values, matching: query)
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(app.tr("Used before")).font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(choices, id: \.self) { choice in
                            Button(choice) {
                                if field == .bank { bank = choice } else { party = choice }
                            }
                            .buttonStyle(.bordered).font(.subheadline)
                            .accessibilityIdentifier(field == .bank ? "bankSuggestion" : "partySuggestion")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachment(_ side: AttachmentSide, data: Data?, selection: Binding<PhotosPickerItem?>) -> some View {
        let photosTitle = app.tr("Photos")
        VStack(alignment: .leading, spacing: 12) {
            Text(app.tr(side == .front ? "Front" : "Back")).font(.subheadline.weight(.semibold))
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 145)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(app.tr("Cheque image"))
            }
            HStack(spacing: 18) {
                Button {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    guard DocumentScanner.isSupported, status != .denied, status != .restricted else {
                        showingCameraHelp = true
                        return
                    }
                    scanSide = side
                    showingScanner = true
                } label: { Label(app.tr("Scan"), systemImage: "camera") }
                .buttonStyle(.borderless)
                PhotosPicker(selection: selection, matching: .images) {
                    Label(photosTitle, systemImage: "photo")
                }
                .buttonStyle(.borderless)
                if data != nil {
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        if side == .front { frontImageData = nil } else { backImageData = nil }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(app.tr("Remove image"))
                }
            }
            .font(.subheadline)
            .disabled(busy)
        }
        .padding(.vertical, 5)
    }

    private func addCustomReminder() {
        let ascii = String(customDays.trimmingCharacters(in: .whitespacesAndNewlines).map { character in
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return character }
            return Character(String(digit))
        })
        guard let days = Int(ascii), (1...365).contains(days) else {
            errorMessage = app.tr("Enter a whole number of days from 1 to 365.")
            return
        }
        if days == 1 { before1 = true }
        else if days == 3 { before3 = true }
        else { customOffsets.insert(days) }
        customDays = ""
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?, side: AttachmentSide) async {
        guard let item else { return }
        isReadingImage = true
        defer {
            isReadingImage = false
            if side == .front { frontPhoto = nil } else { backPhoto = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = app.tr("This image could not be opened. Try another image or enter the details manually.")
                return
            }
            storeImage(image, side: side)
        } catch {
            errorMessage = app.tr("This image could not be opened. Try another image or enter the details manually.")
        }
    }

    @MainActor
    private func storeImage(_ image: UIImage, side: AttachmentSide) {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return }
        let ratio = min(1, 1_800 / longestSide)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let data = normalized.jpegData(compressionQuality: 0.85)
        if side == .front { frontImageData = data } else { backImageData = data }
        imagesExpanded = true
    }

    @MainActor
    private func recognizeFrontImage() async {
        guard let data = frontImageData, let image = UIImage(data: data) else { return }
        guard !currency.isEmpty else {
            errorMessage = app.tr("Choose the app currency in Settings before adding a cheque.")
            return
        }
        isReadingImage = true
        defer { isReadingImage = false }
        do {
            ocrSuggestion = try await ChequeOCRService.recognize(image: image, currencyCode: currency, direction: direction)
        } catch {
            errorMessage = app.tr("The image could not be read. You can enter all details manually.")
        }
    }

    private func applyOCR(_ suggestion: OCRSuggestion, selected: Set<OCRField>) {
        if selected.contains(.number), let value = suggestion.number { number = value }
        if selected.contains(.bank), let value = suggestion.bank {
            bank = value
            extraDetailsExpanded = true
        }
        if selected.contains(.party), let value = suggestion.party { party = value }
        if selected.contains(.amount), let value = suggestion.amountText { amountText = value }
        if selected.contains(.dueDate), let value = suggestion.dueDate { dueDate = value.date() }
    }

    @MainActor
    private func save(addAnother: Bool = false, allowDuplicate: Bool = false) async {
        guard !isSaving else { return }
        guard record?.deletedAt == nil else {
            errorMessage = app.tr("Restore this cheque before changing it.")
            return
        }
        guard record != nil || (!app.currencyConflict && !app.currencyCode.isEmpty) else {
            errorMessage = app.tr("Resolve the currency setting before adding a cheque.")
            return
        }
        guard !currency.isEmpty else {
            errorMessage = app.tr("Choose the app currency in Settings before adding a cheque.")
            return
        }
        guard let amount = CurrencyMath.parseMinorUnits(amountText, currencyCode: currency), amount > 0 else {
            amountError = app.tr("Enter a valid amount greater than zero, using the currency’s decimal places.")
            focusedField = .amount
            return
        }
        if dueDateNeedsReview {
            dateError = app.tr("Review the due date for the next cheque.")
            focusedField = nil
            return
        }
        let due = LocalDay(date: dueDate)
        let issued = includeIssueDate ? LocalDay(date: issueDate) : nil
        if let issued, issued > due {
            dateError = app.tr("The issue date must be on or before the due date.")
            return
        }
        if let issued, let actual = record?.actualDate, issued > actual {
            dateError = app.tr("The actual payment or collection date cannot be before the issue date.")
            return
        }
        if remindersEnabled && !useDefaultReminders && selectedOffsets.isEmpty {
            errorMessage = app.tr("Choose at least one reminder day, or turn reminders off.")
            return
        }
        let maxRank = records.map(\.manualRank).max() ?? -1
        let nextRank = maxRank.addingReportingOverflow(1)
        let snapshot = ChequeSnapshot(
            id: record?.id ?? UUID(), direction: direction, status: record?.status ?? .pending,
            amountMinorUnits: amount, currencyCode: currency, dueDate: due,
            actualDate: record?.actualDate, issueDate: issued,
            number: number.trimmingCharacters(in: .whitespacesAndNewlines),
            bank: bank.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            party: party.trimmingCharacters(in: .whitespacesAndNewlines),
            accountReference: accountReference.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: record?.createdAt ?? Date(),
            manualRank: record?.manualRank ?? (nextRank.overflow ? Int64.max : nextRank.partialValue)
        )
        if !allowDuplicate {
            let matches = ChequeEntryAssistance.probableDuplicateIDs(
                for: snapshot, among: records.filter { $0.deletedAt == nil }.map(\.snapshot), excluding: record?.id
            )
            if !matches.isEmpty {
                duplicateIDs = matches
                pendingAddAnother = addAnother
                focusedField = nil
                showingDuplicate = true
                return
            }
        }
        isSaving = true
        defer { isSaving = false }
        let offsets = useDefaultReminders ? nil : selectedOffsets
        let clock = Calendar(identifier: .gregorian)
        let hour = useDefaultReminders ? nil : clock.component(.hour, from: effectiveReminderTime)
        let minute = useDefaultReminders ? nil : clock.component(.minute, from: effectiveReminderTime)
        if let record {
            record.update(from: snapshot)
            record.frontImageData = frontImageData
            record.backImageData = backImageData
            record.remindersEnabled = remindersEnabled
            record.reminderOffsets = offsets
            record.reminderHour = hour
            record.reminderMinute = minute
        } else {
            context.insert(ChequeRecord(snapshot: snapshot, frontImageData: frontImageData,
                                        backImageData: backImageData, remindersEnabled: remindersEnabled,
                                        reminderOffsets: offsets, reminderHour: hour, reminderMinute: minute))
        }
        do {
            try context.save()
            app.didMutate()
        } catch {
            context.rollback()
            errorMessage = app.tr("The cheque could not be saved. Your draft is still here; please try again.")
            return
        }
        let effectiveOffsets = offsets ?? app.preferences.reminderOffsets
        if remindersEnabled && snapshot.isOutstanding && (!effectiveOffsets.isEmpty || app.preferences.dailySummary) {
            await app.notifications.refreshAuthorization()
            if app.notifications.authorizationStatus == .notDetermined {
                await app.notifications.requestPermission()
                app.didMutate()
            }
        }
        if addAnother && record == nil { resetForNextEntry() } else { dismiss() }
    }

    private func resetForNextEntry() {
        focusedField = nil
        if !keepEntryDetails { direction = .incoming; bank = ""; party = "" }
        amountText = ""; number = ""; branch = ""; accountReference = ""; notes = ""
        dueDate = Date(); issueDate = Date(); includeIssueDate = false
        frontImageData = nil; backImageData = nil; frontPhoto = nil; backPhoto = nil
        remindersEnabled = true; useDefaultReminders = true
        before3 = true; before1 = true; onDueDate = true; customOffsets = []; customDays = ""
        reminderTime = nil; imagesExpanded = false; reminderOptionsExpanded = false
        extraDetailsExpanded = keepEntryDetails && !bank.isEmpty
        amountError = nil; dateError = nil; errorMessage = nil
        duplicateIDs = []; pendingAddAnother = false
        dueDateNeedsReview = true; savedNotice = true
        // Compare with this draft's values, independent of SwiftUI's onChange delivery order.
        cleanFormSignature = formSignature
        entrySequence &+= 1
        DispatchQueue.main.async {
            focusedField = .amount
        }
    }

    private func reminderTitle(_ offset: Int) -> String {
        if offset == 0 { return app.tr("On due date") }
        if offset == 1 { return app.tr("1 day before") }
        if offset == 3 { return app.tr("3 days before") }
        return String(offset) + " " + app.tr("days before")
    }

    private static func clockDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(23, max(0, hour))
        components.minute = min(59, max(0, minute))
        return calendar.date(from: components) ?? Date()
    }
}

private enum AttachmentSide: Equatable { case front, back }
private enum OCRField: Hashable { case number, bank, party, amount, dueDate }

@MainActor
private struct OCRReviewSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let suggestion: OCRSuggestion
    let apply: (Set<OCRField>) -> Void
    @State private var selected: Set<OCRField>

    init(suggestion: OCRSuggestion, apply: @escaping (Set<OCRField>) -> Void) {
        self.suggestion = suggestion
        self.apply = apply
        var fields = Set<OCRField>()
        if suggestion.number != nil { fields.insert(.number) }
        if suggestion.bank != nil { fields.insert(.bank) }
        if suggestion.party != nil { fields.insert(.party) }
        if suggestion.amountText != nil { fields.insert(.amount) }
        if suggestion.dueDate != nil { fields.insert(.dueDate) }
        _selected = State(initialValue: fields)
    }

    var body: some View {
        Form {
            Section {
                Text(app.tr("Check each suggestion against your cheque. Nothing is saved until you tap Save."))
                    .font(.subheadline)
                if suggestion.unsupportedArabic {
                    Label(app.tr("Some Arabic text may need manual entry. You can complete every field yourself."),
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(app.tr("Suggested details")) {
                if let value = suggestion.number { suggestionRow(.number, title: "Cheque number", value: value) }
                if let value = suggestion.bank { suggestionRow(.bank, title: "Bank", value: value) }
                if let value = suggestion.party { suggestionRow(.party, title: "Name", value: value) }
                if let value = suggestion.amountText { suggestionRow(.amount, title: "Amount", value: value) }
                if let value = suggestion.dueDate {
                    suggestionRow(.dueDate, title: "Due date", value: app.formatDay(value))
                }
                if suggestion.number == nil && suggestion.bank == nil && suggestion.party == nil &&
                    suggestion.amountText == nil && suggestion.dueDate == nil {
                    Text(app.tr("No fields were recognized. Keep entering the details manually."))
                        .foregroundStyle(.secondary)
                }
            }
            if !suggestion.recognizedText.isEmpty {
                Section {
                    DisclosureGroup(app.tr("Recognized text")) {
                        Text(suggestion.recognizedText).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(app.tr("Review image details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(app.tr("Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(app.tr("Use selected")) { apply(selected) }
                    .fontWeight(.semibold).disabled(selected.isEmpty)
            }
        }
    }

    private func suggestionRow(_ field: OCRField, title: String, value: String) -> some View {
        Toggle(isOn: Binding(
            get: { selected.contains(field) },
            set: { if $0 { selected.insert(field) } else { selected.remove(field) } }
        )) {
            VStack(alignment: .leading, spacing: 5) {
                Text(app.tr(title)).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body).textSelection(.enabled)
            }
        }
    }
}
