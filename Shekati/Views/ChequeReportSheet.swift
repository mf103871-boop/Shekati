import SwiftUI
import ShekatiCore
import UniformTypeIdentifiers

@MainActor
struct ChequeReportSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let cheques: [ChequeSnapshot]
    @State private var exporting = false
    @State private var document = ChequeTransferDocument(data: Data())
    @State private var failed = false
    var body: some View {
        Form {
            Section {
                LabeledContent(app.tr("Shown cheques"), value: cheques.count.formatted())
                Text(app.tr("The report includes the cheques and order shown in your filtered list."))
                    .foregroundStyle(.secondary)
                Button(app.tr("Save PDF report")) {
                    document = ChequeTransferDocument(data: ChequePDFReport.generate(cheques: cheques, language: app.preferences.language))
                    exporting = true
                }.disabled(cheques.isEmpty)
                Button(app.tr("Save CSV of shown cheques")) {
                    csvDocument = ChequeTransferDocument(data: ChequeCSV.export(cheques))
                    exportingCSV = true
                }.disabled(cheques.isEmpty)
            } footer: {
                Text(app.tr("Exported files contain readable cheque details. Share only with people you choose."))
            }
        }.navigationTitle(app.tr("Cheque report"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Done")) { dismiss() } } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .pdf,
                      defaultFilename: "Shekati-report-\(LocalDay.today.iso).pdf") { result in
            if case .failure = result { failed = true }
        }
        .fileExporter(isPresented: $exportingCSV, document: csvDocument, contentType: .commaSeparatedText,
                      defaultFilename: "Shekati-filtered-\(LocalDay.today.iso).csv") { result in
            if case .failure = result { failed = true }
        }
        .alert(app.tr("The file could not be saved. Please try again."), isPresented: $failed) {
            Button(app.tr("OK"), role: .cancel) {}
        }
    }
    @State private var exportingCSV = false
    @State private var csvDocument = ChequeTransferDocument(data: Data())
}
