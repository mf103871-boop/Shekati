import UIKit
import ShekatiCore

@MainActor
enum CashFlowReport {
    struct Row {
        let label: String
        let amount: String
    }

    static func rows(for outlook: AccountOutlook, currency: String, language: AppLanguage) -> [Row] {
        func money(_ minor: Int64) -> String {
            DisplayFormatting.amount(minorUnits: minor, currencyCode: currency, locale: language.locale)
        }
        let summary = [("Recorded balance", outlook.recorded), ("Outgoing due within 7 days", outlook.outgoing7),
                       ("Expected incoming within 7 days", outlook.incoming7), ("Estimated available within 7 days", outlook.available7)]
        return summary.map { Row(label: Localization.text($0.0, language: language), amount: money($0.1)) }
            + outlook.points.map { Row(label: DisplayFormatting.day($0.day, locale: language.locale), amount: money($0.balance)) }
    }

    static func generate(_ outlook: AccountOutlook, account: BankAccountRecord, language: AppLanguage) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let direction = NSMutableParagraphStyle()
        direction.alignment = language.isRTL ? .right : .left
        direction.baseWritingDirection = language.isRTL ? .rightToLeft : .leftToRight
        let rows = rows(for: outlook, currency: account.currencyCode, language: language)
        func draw(_ value: String, in rect: CGRect, font: UIFont) {
            (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: direction])
        }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var y = page.height
            for row in rows {
                if y + 44 > page.height - 45 {
                    context.beginPage()
                    draw(Localization.text("Cash forecast", language: language), in: CGRect(x: 32, y: 28, width: 531, height: 38), font: .boldSystemFont(ofSize: 22))
                    draw(account.name + " · " + account.currencyCode, in: CGRect(x: 32, y: 75, width: 531, height: 34), font: .systemFont(ofSize: 15))
                    draw(Localization.text("Assumes incoming cheques are collected on their due dates.", language: language),
                         in: CGRect(x: 32, y: 117, width: 531, height: 50), font: .systemFont(ofSize: 12))
                    y = 181
                }
                draw(row.label, in: CGRect(x: language.isRTL ? 235 : 32, y: y, width: 328, height: 40), font: .systemFont(ofSize: 13))
                draw(row.amount, in: CGRect(x: language.isRTL ? 32 : 372, y: y, width: 191, height: 40), font: .boldSystemFont(ofSize: 13))
                y += 44
            }
        }
    }
}

