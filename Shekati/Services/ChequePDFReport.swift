import Foundation
import UIKit
import ShekatiCore

@MainActor
enum ChequePDFReport {
    static func generate(cheques: [ChequeSnapshot], language: AppLanguage) -> Data {
        let arabic = language == .arabic
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let totals = totalsText(cheques: cheques, language: language)
        return renderer.pdfData { context in
            var index = 0
            var pageNumber = 0
            repeat {
                context.beginPage(); pageNumber += 1
                draw(arabic ? "شيكاتي — كشف الشيكات" : "Shekati — Cheque report", in: CGRect(x: 32, y: 30, width: 531, height: 32),
                     font: .boldSystemFont(ofSize: 22), arabic: arabic)
                draw((arabic ? "تاريخ الكشف: " : "Report date: ") + DisplayFormatting.day(.today, locale: language.locale) + "    ·    " +
                     (arabic ? "عدد الشيكات: " : "Cheques: ") + String(cheques.count),
                     in: CGRect(x: 32, y: 68, width: 531, height: 22), font: .systemFont(ofSize: 11), arabic: arabic)
                draw(totals, in: CGRect(x: 32, y: 96, width: 531, height: 42),
                     font: .boldSystemFont(ofSize: 12), arabic: arabic)
                draw(arabic ? "الاسم / الرقم / البنك / الحالة" : "Name / number / bank / status",
                     in: CGRect(x: arabic ? 269 : 32, y: 143, width: 294, height: 25), font: .boldSystemFont(ofSize: 12), arabic: arabic)
                draw(arabic ? "المبلغ / الاستحقاق" : "Amount / due date",
                     in: CGRect(x: arabic ? 32 : 352, y: 143, width: 211, height: 25), font: .boldSystemFont(ofSize: 12), arabic: arabic)
                var y: CGFloat = 174
                while index < cheques.count && y + 80 <= 785 {
                    let cheque = cheques[index]
                    let color = index.isMultiple(of: 2) ? UIColor(white: 0.96, alpha: 1) : UIColor.white
                    color.setFill(); UIBezierPath(rect: CGRect(x: 28, y: y - 3, width: 539, height: 78)).fill()
                    let name = cheque.party.isEmpty ? (arabic ? "شيك" : "Cheque") : cheque.party
                    let direction = cheque.direction == .incoming ? (arabic ? "وارد" : "Incoming") : (arabic ? "صادر" : "Outgoing")
                    let details = [cheque.number.isEmpty ? "" : "#" + cheque.number, cheque.bank]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    draw(name, in: CGRect(x: arabic ? 269 : 32, y: y, width: 294, height: 27),
                         font: .boldSystemFont(ofSize: 13), arabic: arabic)
                    draw(details, in: CGRect(x: arabic ? 269 : 32, y: y + 28, width: 294, height: 20),
                         font: .systemFont(ofSize: 10), arabic: arabic)
                    draw(direction + " · " + status(cheque, arabic: arabic),
                         in: CGRect(x: arabic ? 269 : 32, y: y + 52, width: 294, height: 20),
                         font: .systemFont(ofSize: 10), arabic: arabic)
                    let amount = DisplayFormatting.amount(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode, locale: language.locale)
                    draw(amount, in: CGRect(x: arabic ? 32 : 352, y: y, width: 211, height: 30),
                         font: .boldSystemFont(ofSize: 13), arabic: arabic)
                    draw(DisplayFormatting.day(cheque.dueDate, locale: language.locale), in: CGRect(x: arabic ? 32 : 352, y: y + 33, width: 211, height: 25),
                         font: .systemFont(ofSize: 12), arabic: arabic)
                    index += 1; y += 83
                }
                draw((arabic ? "صفحة " : "Page ") + String(pageNumber),
                     in: CGRect(x: 32, y: 809, width: 531, height: 18), font: .systemFont(ofSize: 10), arabic: arabic)
            } while index < cheques.count
        }
    }

    private static func totalsText(cheques: [ChequeSnapshot], language: AppLanguage) -> String {
        let arabic = language == .arabic
        let groups = Dictionary(grouping: cheques, by: { "\($0.currencyCode)|\($0.direction.rawValue)" })
        return groups.keys.sorted().compactMap { key -> String? in
            guard let values = groups[key], let first = values.first else { return nil }
            var total: Int64 = 0
            var overflow = false
            for value in values {
                let next = total.addingReportingOverflow(value.amountMinorUnits)
                if next.overflow { overflow = true; break }
                total = next.partialValue
            }
            let type = first.direction == .incoming ? (arabic ? "وارد" : "Incoming") : (arabic ? "صادر" : "Outgoing")
            let amount = overflow ? (arabic ? "المجموع يتجاوز الحد" : "Total exceeds limit") :
                DisplayFormatting.amount(minorUnits: total, currencyCode: first.currencyCode, locale: language.locale)
            return type + ": " + amount
        }.joined(separator: "    ·    ")
    }

    private static func status(_ cheque: ChequeSnapshot, arabic: Bool) -> String {
        switch cheque.status {
        case .pending: return arabic ? "معلّق" : "Pending"
        case .returned: return arabic ? "مرتجع" : "Returned"
        case .cancelled: return arabic ? "ملغى" : "Cancelled"
        case .settled:
            return cheque.direction == .incoming ? (arabic ? "تم التحصيل" : "Collected") : (arabic ? "تم الصرف" : "Paid")
        }
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, arabic: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = arabic ? .right : .left
        paragraph.baseWritingDirection = arabic ? .rightToLeft : .leftToRight
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.black,
                                                        .paragraphStyle: paragraph])
    }
}
