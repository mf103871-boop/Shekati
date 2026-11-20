import SwiftData
import SwiftUI
import ShekatiCore
import UniformTypeIdentifiers

@MainActor
struct ChequeReportRows {
    let originals: [ChequeSnapshot]
    let outstanding: [ChequeSnapshot]
    let disputedCurrencies: Set<String>

    init(ids: [UUID], records: [ChequeRecord], events: [LedgerEventRecord]) {
        let audit = ChequeAudit(records: records, events: events)
        let byID = Dictionary(records.filter(\.isActive).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let included = ids.compactMap { byID[$0] }
        let disputed = Set(included.filter { audit.disputed.contains($0.id) }.map(\.currencyCode))
        originals = included.map { record in
            var snapshot = record.snapshot
            if let state = audit.positions[record.id]?.legacyStatus { snapshot.status = state }
            return snapshot
        }
        outstanding = included.filter { !disputed.contains($0.currencyCode) }
            .compactMap { $0.snapshot.remainingObligation(using: audit.positions[$0.id]) }
        disputedCurrencies = disputed
    }

    var canExportRemaining: Bool { !outstanding.isEmpty && disputedCurrencies.isEmpty }
}

@MainActor
struct ChequeReportSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [ChequeRecord]
    @Query private var events: [LedgerEventRecord]
    let chequeIDs: [UUID]
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    @State private var basis = ChequePDFReport.Basis.original
    @State private var exporting = false
    @State private var exportingCSV = false
    @State private var document = ChequeTransferDocument(data: Data())
    @State private var failed = false

    var body: some View {
        let rows = ChequeReportRows(ids: chequeIDs, records: records, events: events)
        Form {
            Section {
                LabeledContent(app.tr("Shown cheques"), value: DisplayFormatting.count(rows.originals.count, locale: app.preferences.language.locale))
                Text(app.tr("The report includes the cheques and order shown in your filtered list.")).foregroundStyle(.secondary)
                ForEach(rows.disputedCurrencies.sorted(), id: \.self) { code in UnverifiedCurrencyTotal(currency: code) }
                if hidesAmounts {
                    Button(app.tr("Show amounts")) { hidesAmounts = false }
                } else {
                    Button(app.tr("Save PDF report") + " · " + app.tr("Original amount")) {
                        exportPDF(rows.originals, basis: .original)
                    }.disabled(rows.originals.isEmpty)
                    Button(app.tr("Save PDF report") + " · " + app.tr("Remaining amount")) {
                        exportPDF(rows.outstanding, basis: .remaining)
                    }.disabled(!rows.canExportRemaining).accessibilityIdentifier("remainingPDF")
                    Button(app.tr("Save CSV of shown cheques")) {
                        document = ChequeTransferDocument(data: ChequeCSV.export(rows.originals))
                        exportingCSV = true
                    }.disabled(rows.originals.isEmpty)
                }
            } footer: {
                Text(app.tr("Exported files contain readable cheque details. Share only with people you choose."))
            }
        }.navigationTitle(app.tr("Cheque report"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Done")) { dismiss() } } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .pdf,
                      defaultFilename: "Shekati-\(basis.rawValue)-\(LocalDay.today.iso).pdf") { result in
            if case .failure = result { failed = true }
        }
        .fileExporter(isPresented: $exportingCSV, document: document, contentType: .commaSeparatedText,
                      defaultFilename: "Shekati-filtered-\(LocalDay.today.iso).csv") { result in
            if case .failure = result { failed = true }
        }
        .alert(app.tr("The file could not be saved. Please try again."), isPresented: $failed) {
            Button(app.tr("OK"), role: .cancel) {}
        }
    }

    private func exportPDF(_ rows: [ChequeSnapshot], basis: ChequePDFReport.Basis) {
        guard !hidesAmounts else { return }
        self.basis = basis
        document = ChequeTransferDocument(data: ChequePDFReport.generate(cheques: rows, language: app.preferences.language, basis: basis))
        exporting = true
    }
}
