import XCTest
import ShekatiCore
@testable import Shekati

final class ChequeOCRParserTests: XCTestCase {
    func testLabeledEnglishFieldsAndGroupedAmount() {
        let text = "Cheque No: 000123\nBank: Example Bank\nPay to: Local Supplies\nAmount (JOD): 1,250.500\nDue date: 2026-10-25"
        let value = ChequeOCRParser.parse(text: text, currencyCode: "JOD", direction: .outgoing)
        XCTAssertEqual(value.number, "000123")
        XCTAssertEqual(value.bank, "Example Bank")
        XCTAssertEqual(value.party, "Local Supplies")
        XCTAssertEqual(value.amountText, "1250.500")
        XCTAssertEqual(value.dueDate?.iso, "2026-10-25")
        XCTAssertEqual(value.recognizedText, text)
    }

    func testArabicDigitsAndDecimalSeparatorsAreNormalizedWithoutLosingNumberZeros() {
        let text = "رقم الشيك: ٠٠٠١٢٣\nالبنك: بنك الاختبار\nالمستفيد: شركة الاختبار\nالمبلغ: ١٬٢٥٠٫٥٠٠\nتاريخ الاستحقاق: ٢٥/١٠/٢٠٢٦"
        let value = ChequeOCRParser.parse(text: text, currencyCode: "JOD", direction: .outgoing, unsupportedArabic: true)
        XCTAssertEqual(value.number, "000123")
        XCTAssertEqual(value.bank, "بنك الاختبار")
        XCTAssertEqual(value.party, "شركة الاختبار")
        XCTAssertEqual(value.amountText, "1250.500")
        XCTAssertEqual(value.dueDate?.iso, "2026-10-25")
        XCTAssertTrue(value.unsupportedArabic)
    }

    func testAmbiguousOrUnlabeledDatesNeverBecomeDueDates() {
        XCTAssertNil(ChequeOCRParser.parse(text: "Due date: 05/06/2026", currencyCode: "USD").dueDate)
        XCTAssertNil(ChequeOCRParser.parse(text: "Issue date: 2026-10-25\n2026-11-01", currencyCode: "USD").dueDate)
        XCTAssertNil(ChequeOCRParser.parse(text: "Due date: 2026-02-30", currencyCode: "USD").dueDate)
        XCTAssertEqual(ChequeOCRParser.parse(text: "Due date: 10/25/2026", currencyCode: "USD").dueDate?.iso, "2026-10-25")
    }

    func testConflictingLabeledValuesRequireManualEntry() {
        let value = ChequeOCRParser.parse(text: "Cheque No: 1234\nCheque No: 9999\nDue date: 2026-10-25\nMaturity date: 2026-10-26", currencyCode: "USD")
        XCTAssertNil(value.number)
        XCTAssertNil(value.dueDate)
    }

    func testAmountPrecisionAndMixedSeparatorsDoNotGuessFinancialValues() {
        XCTAssertNil(ChequeOCRParser.parse(text: "Amount: 1.250,50", currencyCode: "EUR").amountText)
        XCTAssertNil(ChequeOCRParser.parse(text: "Amount: 25.123", currencyCode: "USD").amountText)
        XCTAssertNil(ChequeOCRParser.parse(text: "Amount: 0", currencyCode: "USD").amountText)
        XCTAssertNil(ChequeOCRParser.parse(text: "Amount in words: one thousand", currencyCode: "USD").amountText)
        XCTAssertEqual(ChequeOCRParser.parse(text: "Amount: 25", currencyCode: "JPY").amountText, "25")
        XCTAssertNil(ChequeOCRParser.parse(text: "Amount: 1,250", currencyCode: "JOD").amountText)
    }

    func testLabelOnSeparateLineIsSupported() {
        let value = ChequeOCRParser.parse(text: "Cheque No\n000123\nDue date\n2026-10-25", currencyCode: "USD")
        XCTAssertEqual(value.number, "000123")
        XCTAssertEqual(value.dueDate?.iso, "2026-10-25")
    }

    func testGermanChequeUsesAppLanguageForAmountsDatesAndPartyRoles() {
        let text = """
        Schecknummer: 000241
        Bank: Musterbank
        Aussteller: Winter GmbH
        Zahlungsempfänger: Hafen GmbH
        Betrag: EUR 1.250,50
        Fälligkeit: 25.10.2026
        """
        let incoming = ChequeOCRParser.parse(text: text, currencyCode: "EUR", direction: .incoming, languageCode: "de")
        XCTAssertEqual(incoming.number, "000241")
        XCTAssertEqual(incoming.party, "Winter GmbH")
        XCTAssertEqual(incoming.bank, "Musterbank")
        XCTAssertEqual(incoming.amountText, "1250.50")
        XCTAssertEqual(incoming.dueDate?.iso, "2026-10-25")
        let outgoing = ChequeOCRParser.parse(text: text, currencyCode: "EUR", direction: .outgoing, languageCode: "de")
        XCTAssertEqual(outgoing.party, "Hafen GmbH")

        let uncertain = ChequeOCRParser.parse(text: "Betrag: 1,250\nFälligkeit: 05.06.2026", currencyCode: "JOD", languageCode: "de")
        XCTAssertNil(uncertain.amountText)
        XCTAssertNil(uncertain.dueDate)
        XCTAssertNil(ChequeOCRParser.parse(text: "Betrag -200", currencyCode: "EUR", languageCode: "de").amountText)
        let duplicate = ChequeOCRParser.parse(text: "Betrag: 20,55\nBetrag: 3,555", currencyCode: "EUR", languageCode: "de")
        XCTAssertNil(duplicate.amountText)
    }

    func testFrenchChequeUsesSpacedGroupingAndStraightApostropheInPrintedLabel() {
        let text = """
        Numéro de chèque : 000743
        Banque : Banque de démonstration
        Bénéficiaire : Atelier Rivage
        Montant : 1\u{202F}250,50 EUR
        Date d'échéance : 25/10/2026
        """
        let result = ChequeOCRParser.parse(text: text, currencyCode: "EUR", direction: .outgoing, languageCode: "fr")
        XCTAssertEqual(result.number, "000743")
        XCTAssertEqual(result.bank, "Banque de démonstration")
        XCTAssertEqual(result.party, "Atelier Rivage")
        XCTAssertEqual(result.amountText, "1250.50")
        XCTAssertEqual(result.dueDate?.iso, "2026-10-25")
        XCTAssertNil(ChequeOCRParser.parse(text: "Montant : 12 50,50", currencyCode: "EUR", languageCode: "fr").amountText)
    }

    func testJapaneseChequeAcceptsFullwidthDelimitersAndPreservesRecognizedText() {
        let text = """
        小切手番号：０００１２６
        銀行：試験銀行
        金額：１２，５００
        支払期日：２０２６／１０／２５
        """
        let result = ChequeOCRParser.parse(text: text, currencyCode: "JPY", languageCode: "ja")
        XCTAssertEqual(result.number, "000126")
        XCTAssertEqual(result.bank, "試験銀行")
        XCTAssertEqual(result.amountText, "12500")
        XCTAssertEqual(result.dueDate?.iso, "2026-10-25")
        XCTAssertEqual(result.recognizedText, text)
        XCTAssertNil(ChequeOCRParser.parse(text: "銀行員：佐藤", currencyCode: "JPY", languageCode: "ja").bank)
    }

    func testSuggestedChequeNumbersAreDigitsOnlyAndKeepLeadingZeros() {
        for input in ["A000123", "000-123", "000/123", "000 123", "+000123", "000123!"] {
            XCTAssertNil(ChequeOCRParser.parse(text: "Cheque No: " + input, currencyCode: "USD").number, input)
        }
        let text = "رقم الشيك: ۰۰۰۱۲۳\nالمبلغ: ۲۵٫۵۰"
        let value = ChequeOCRParser.parse(text: text, currencyCode: "USD")
        XCTAssertEqual(value.number, "000123")
        XCTAssertEqual(value.amountText, "25.50")
        XCTAssertEqual(value.recognizedText, text, "Raw OCR evidence stays intact; the numeric suggestion is normalized")
        XCTAssertEqual(ChequeOCRParser.parse(text: "Cheque No: ０００１２３", currencyCode: "USD").number, "000123")
    }

    func testIncomingAndOutgoingUseTheCorrectCounterpartyRole() {
        let text = "Payer: Buyer Company\nPayee: Seller Company"
        XCTAssertEqual(ChequeOCRParser.parse(text: text, currencyCode: "USD", direction: .incoming).party, "Buyer Company")
        XCTAssertEqual(ChequeOCRParser.parse(text: text, currencyCode: "USD", direction: .outgoing).party, "Seller Company")
        XCTAssertNil(ChequeOCRParser.parse(text: text, currencyCode: "USD").party)
        XCTAssertNil(ChequeOCRParser.parse(text: "Payee: Seller Company", currencyCode: "USD", direction: .incoming).party)
        XCTAssertNil(ChequeOCRParser.parse(text: "Drawer: Buyer Company", currencyCode: "USD", direction: .outgoing).party)
        XCTAssertEqual(ChequeOCRParser.parse(text: "الساحب: شركة المشتري\nالمستفيد: شركة البائع", currencyCode: "JOD", direction: .incoming).party, "شركة المشتري")
        XCTAssertEqual(ChequeOCRParser.parse(text: "الساحب: شركة المشتري\nالمستفيد: شركة البائع", currencyCode: "JOD", direction: .outgoing).party, "شركة البائع")
    }
}
