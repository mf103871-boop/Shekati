import SwiftUI

@MainActor
struct ChequeSettlementSheet: View {
    @Environment(AppState.self) private var app
    @EnvironmentObject private var plus: ShekatiPlusStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shekati.hideAmounts") private var hidesAmounts = false
    let record: ChequeRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                ChequeOperationsView(record: record, isPlus: plus.isPlus, hidesAmounts: hidesAmounts)
                    .padding()
            }
            .navigationTitle(app.tr("Cheque details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.tr("Done")) { dismiss() } } }
        }
    }
}
