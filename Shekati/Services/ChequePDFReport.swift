import Foundation
import UIKit
import ShekatiCore

@MainActor
enum ChequePDFReport {
    enum Basis: String {
        case original, remaining
        var title: String { self == .original ? "Original amount" : "Remaining amount" }
    }
    static func generate(cheques: [ChequeSnapshot], language: AppLanguage, basis: Basis = .original) -> Data {
        let arabic = language.isRTL
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let totals = totalsText(cheques: cheques, language: language)
        let reportDate = DisplayFormatting.day(.today, locale: language.locale)
        let bodyTop: CGFloat = 174
        let bodyBottom: CGFloat = 785
        return renderer.pdfData { context in
            var pageNumber = 1
            context.beginPage()
            drawHeader(reportDate: reportDate, count: cheques.count, totals: totals, language: language, basis: basis)
            var y = bodyTop
            for (index, cheque) in cheques.enumerated() {
                let layout = ReportRowLayout(text: rowText(cheque, language: language), width: 294)
                // Keep an ordinary wrapped row together. An extraordinary row flows across
                // TextKit containers, which preserve glyph clusters and Arabic shaping.
                if layout.fullHeight <= bodyBottom - bodyTop && y > bodyTop && y + layout.fullHeight > bodyBottom {
                    drawFooter(pageNumber, language: language)
                    context.beginPage(); pageNumber += 1
                    drawHeader(reportDate: reportDate, count: cheques.count, totals: totals, language: language, basis: basis)
                    y = bodyTop
                }
                var continuation = false
                while layout.hasMore {
                    if bodyBottom - y < 78 {
                        drawFooter(pageNumber, language: language)
                        context.beginPage(); pageNumber += 1
                        drawHeader(reportDate: reportDate, count: cheques.count, totals: totals, language: language, basis: basis)
                        y = bodyTop
                    }
                    let fragment = layout.nextFragment(height: bodyBottom - y - 12)
                    let rowHeight = max(78, ceil(fragment.height) + 12)
                    let color = index.isMultiple(of: 2) ? UIColor(white: 0.96, alpha: 1) : UIColor.white
                    color.setFill(); UIBezierPath(rect: CGRect(x: 28, y: y, width: 539, height: rowHeight)).fill()
                    layout.draw(fragment, at: CGPoint(x: arabic ? 269 : 32, y: y + 6))
                    let amount = DisplayFormatting.amount(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode, locale: language.locale)
                    draw(amount, in: CGRect(x: arabic ? 32 : 352, y: y + 6, width: 211, height: 30),
                         font: .boldSystemFont(ofSize: 13), arabic: arabic)
                    draw(DisplayFormatting.day(cheque.dueDate, locale: language.locale), in: CGRect(x: arabic ? 32 : 352, y: y + 36, width: 211, height: 25),
                         font: .systemFont(ofSize: 12), arabic: arabic)
                    if continuation {
                        draw((Localization.text("Cheque continuation", language: language) + " ") + String(index + 1),
                             in: CGRect(x: arabic ? 32 : 352, y: y + 60, width: 211, height: 16),
                             font: .systemFont(ofSize: 9), arabic: arabic)
                    }
                    y += rowHeight + 5
                    if layout.hasMore {
                        drawFooter(pageNumber, language: language)
                        context.beginPage(); pageNumber += 1
                        drawHeader(reportDate: reportDate, count: cheques.count, totals: totals, language: language, basis: basis)
                        y = bodyTop; continuation = true
                    }
                }
            }
            drawFooter(pageNumber, language: language)
        }
    }

    private static func drawHeader(reportDate: String, count: Int, totals: String, language: AppLanguage, basis: Basis) {
        let arabic = language.isRTL
        draw(Localization.text("Shekati — Cheque report", language: language) + " · " + Localization.text(basis.title, language: language), in: CGRect(x: 32, y: 30, width: 531, height: 32),
             font: .boldSystemFont(ofSize: 22), arabic: arabic)
        draw((Localization.text("Report date:", language: language) + " ") + reportDate + "    ·    " +
             (Localization.text("Cheques:", language: language) + " ") + String(count),
             in: CGRect(x: 32, y: 68, width: 531, height: 22), font: .systemFont(ofSize: 11), arabic: arabic)
        draw(totals, in: CGRect(x: 32, y: 96, width: 531, height: 42), font: .boldSystemFont(ofSize: 12), arabic: arabic)
        draw(Localization.text("Name / number / bank / status", language: language),
             in: CGRect(x: arabic ? 269 : 32, y: 143, width: 294, height: 25), font: .boldSystemFont(ofSize: 12), arabic: arabic)
        draw(Localization.text("Amount / due date", language: language),
             in: CGRect(x: arabic ? 32 : 352, y: 143, width: 211, height: 25), font: .boldSystemFont(ofSize: 12), arabic: arabic)
    }

    private static func drawFooter(_ page: Int, language: AppLanguage) {
        let arabic = language.isRTL
        draw((Localization.text("Page", language: language) + " ") + String(page), in: CGRect(x: 32, y: 809, width: 531, height: 18),
             font: .systemFont(ofSize: 10), arabic: arabic)
    }

    private static func rowText(_ cheque: ChequeSnapshot, language: AppLanguage) -> NSAttributedString {
        let arabic = language.isRTL
        let result = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = arabic ? .right : .left
        paragraph.baseWritingDirection = arabic ? .rightToLeft : .leftToRight
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2; paragraph.paragraphSpacing = 5
        func append(_ text: String, font: UIFont) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black,
                                                              .paragraphStyle: paragraph]
            if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
            result.append(NSAttributedString(string: NumericInput.latinDigits(text), attributes: attributes))
        }
        append(cheque.party.isEmpty ? (Localization.text("Cheque", language: language)) : cheque.party, font: .boldSystemFont(ofSize: 13))
        if !cheque.number.isEmpty { append("#" + NumericInput.latinDigits(cheque.number), font: .systemFont(ofSize: 10)) }
        if !cheque.bank.isEmpty { append(cheque.bank, font: .systemFont(ofSize: 10)) }
        let direction = cheque.direction == .incoming ? (Localization.text("Incoming", language: language)) : (Localization.text("Outgoing", language: language))
        append(direction + " · " + status(cheque, language: language), font: .systemFont(ofSize: 10))
        return result
    }

    private static func totalsText(cheques: [ChequeSnapshot], language: AppLanguage) -> String {
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
            let type = first.direction == .incoming ? (Localization.text("Incoming", language: language)) : (Localization.text("Outgoing", language: language))
            let amount = overflow ? (Localization.text("Total exceeds limit", language: language)) :
                DisplayFormatting.amount(minorUnits: total, currencyCode: first.currencyCode, locale: language.locale)
            return type + ": " + amount
        }.joined(separator: "    ·    ")
    }

    private static func status(_ cheque: ChequeSnapshot, language: AppLanguage) -> String {
        switch cheque.status {
        case .pending: return Localization.text("Pending", language: language)
        case .returned: return Localization.text("Returned", language: language)
        case .cancelled: return Localization.text("Cancelled", language: language)
        case .settled:
            return cheque.direction == .incoming ? (Localization.text("Collected", language: language)) : (Localization.text("Paid", language: language))
        }
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, arabic: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = arabic ? .right : .left
        paragraph.baseWritingDirection = arabic ? .rightToLeft : .leftToRight
        paragraph.lineBreakMode = .byWordWrapping
        (NumericInput.latinDigits(text) as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.black,
                                                        .paragraphStyle: paragraph])
    }

    @MainActor
    private final class ReportRowLayout {
        struct Fragment {
            let range: NSRange
            let height: CGFloat
        }
        private let storage: NSTextStorage
        private let manager: NSLayoutManager
        private let width: CGFloat
        private var consumedGlyphs = 0
        private let glyphCount: Int
        let fullHeight: CGFloat
        var hasMore: Bool { consumedGlyphs < glyphCount }

        init(text: NSAttributedString, width: CGFloat) {
            let textStorage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager()
            textStorage.addLayoutManager(layout)
            let measuring = NSTextContainer(size: CGSize(width: width, height: 1_000_000))
            measuring.lineFragmentPadding = 0
            layout.addTextContainer(measuring)
            layout.ensureLayout(for: measuring)
            glyphCount = layout.numberOfGlyphs
            fullHeight = max(78, ceil(layout.usedRect(for: measuring).height) + 12)
            layout.removeTextContainer(at: 0)
            storage = textStorage; manager = layout; self.width = width
        }

        func nextFragment(height: CGFloat) -> Fragment {
            let container = NSTextContainer(size: CGSize(width: width, height: max(66, height)))
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            let range = manager.glyphRange(for: container)
            consumedGlyphs = NSMaxRange(range)
            return Fragment(range: range, height: manager.usedRect(for: container).height)
        }

        func draw(_ fragment: Fragment, at origin: CGPoint) {
            manager.drawBackground(forGlyphRange: fragment.range, at: origin)
            manager.drawGlyphs(forGlyphRange: fragment.range, at: origin)
        }
    }
}
