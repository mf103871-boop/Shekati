import Foundation
import SwiftData
import ShekatiCore
import UIKit

/// Fixtures can populate only the UI tests' in-memory simulator container.
@MainActor
enum StoreScreenshotFixtures {
    static var referenceDay: LocalDay { .today }
    static func seedIfRequested(in container: ModelContainer, language: AppLanguage) throws {
        #if DEBUG && targetEnvironment(simulator)
        let args = CommandLine.arguments
        guard args.contains("--ui-testing"), args.contains("--store-screens") else { return }
        let context = container.mainContext
        guard try context.fetchCount(FetchDescriptor<ChequeRecord>()) == 0 else { return }
        let ar = language == .arabic
        let account = BankAccountRecord(name: Localization.text("Current account", language: language),
                                        currencyCode: "JOD", openingMinor: 8_450_000)
        let book = ChequeBookRecord(accountID: account.id, name: ar ? "دفتر الشركة" : "Atlas")
        context.insert(AppConfiguration(currencyCode: "JOD"))
        context.insert(account)
        context.insert(book)
        let rows: [(String, String, String, ChequeDirection, Int64, Int)] = [
            ("00000000-0000-4000-8000-000000004182", "004182", ar ? "شركة المدار" : "Al Madar", .incoming, 1_250_000, 0),
            ("00000000-0000-4000-8000-000000007309", "007309", ar ? "مؤسسة الأفق" : "Horizon", .outgoing, 1_800_000, 5),
            ("00000000-0000-4000-8000-000000007310", "007310", ar ? "شركة الإمداد" : "Meridian", .outgoing, 1_400_000, 6),
            ("00000000-0000-4000-8000-000000004185", "004185", ar ? "شركة المسار" : "Atlas", .incoming, 3_500_000, 7),
            ("00000000-0000-4000-8000-000000007311", "007311", ar ? "مؤسسة البناء" : "Summit", .outgoing, 10_650_000, 13)
        ]
        for (uuid, number, party, direction, amount, offset) in rows {
            guard let id = UUID(uuidString: uuid) else { continue }
            let due = referenceDay.adding(days: offset)
            let snapshot = ChequeSnapshot(id: id, direction: direction, amountMinorUnits: amount,
                currencyCode: "JOD", dueDate: due, number: number, bank: "Atlas", party: party)
            let image = number == "004182" ? sampleCheque(due: due) : nil
            let record = ChequeRecord(snapshot: snapshot, frontImageData: image, remindersEnabled: false)
            record.bankAccountID = account.id
            record.chequeBookID = direction == .outgoing ? book.id : nil
            context.insert(record)
        }
        try context.save()
        #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private static func sampleCheque(due: LocalDay) -> Data? {
        let size = CGSize(width: 1040, height: 500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(red: 0.93, green: 0.97, blue: 0.94, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.17, green: 0.36, blue: 0.31, alpha: 1).setStroke()
            context.cgContext.stroke(CGRect(x: 12, y: 12, width: 1016, height: 476))
            let fields = ["SAMPLE  /  SPECIMEN", "Cheque number: 004182", "Bank: Atlas", "Payer: Al Madar", "Amount (JOD): 1250.000", "Due date: " + due.iso]
            for (i, line) in fields.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 38, y: CGFloat(30 + 70 * i)), withAttributes: [
                    .font: UIFont.systemFont(ofSize: i == 0 ? 32 : 36, weight: i == 0 ? .semibold : .regular),
                    .foregroundColor: UIColor(red: 0.09, green: 0.20, blue: 0.19, alpha: 1)
                ])
            }
        }.jpegData(compressionQuality: 0.95)
    }
    #endif
}
