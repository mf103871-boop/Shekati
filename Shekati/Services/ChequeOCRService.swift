import Foundation
import UIKit
import Vision
import ImageIO
import ShekatiCore

struct OCRSuggestion: Equatable, Sendable {
    var number: String?
    var bank: String?
    var party: String?
    var amountText: String?
    var dueDate: LocalDay?
    var recognizedText: String
    var unsupportedArabic: Bool
}

enum OCRRecognitionError: LocalizedError {
    case invalidImage, noText
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "تعذر قراءة صورة الشيك. / The cheque image could not be read."
        case .noText: return "لم يظهر نص واضح. يمكنك إدخال المعلومات يدويًا. / No clear text was found. Enter the details manually."
        }
    }
}

enum ChequeOCRService {
    /// Vision runs on the device. A suggestion is never a saved or validated financial record.
    static func recognize(image: UIImage, currencyCode: String, direction: ChequeDirection? = nil,
                          languageCode: String = Locale.preferredLanguages.first ?? "en") async throws -> OCRSuggestion {
        guard let cgImage = image.cgImage else { throw OCRRecognitionError.invalidImage }
        let orientation = image.imageOrientation.cgOrientation
        return try await Task.detached(priority: .userInitiated) {
            let result: (text: String, supportsArabic: Bool)
            do {
                result = try read(cgImage, orientation: orientation, level: .accurate, language: languageCode)
            } catch {
                result = try read(cgImage, orientation: orientation, level: .fast, language: languageCode)
            }
            return ChequeOCRParser.parse(text: result.text, currencyCode: currencyCode, direction: direction,
                                         unsupportedArabic: !result.supportsArabic, languageCode: languageCode)
        }.value
    }

    private static func read(_ image: CGImage, orientation: CGImagePropertyOrientation,
                             level: VNRequestTextRecognitionLevel, language: String) throws -> (text: String, supportsArabic: Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        #if targetEnvironment(simulator)
        // A hosted simulator may not expose a Metal or Neural Engine device to Vision.
        request.usesCPUOnly = true
        #endif
        let supported = try request.supportedRecognitionLanguages()
        let primary = Locale(identifier: language).language.languageCode?.identifier ?? "en"
        var selected: [String] = []
        for code in [primary, "en", "ar"] {
            if let language = supported.first(where: { $0.lowercased().hasPrefix(code.lowercased()) }), !selected.contains(language) {
                selected.append(language)
            }
        }
        if !selected.isEmpty { request.recognitionLanguages = selected }
        request.automaticallyDetectsLanguage = level == .accurate && selected.count > 1
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRRecognitionError.noText }
        return (text, supported.contains { $0.lowercased().hasPrefix("ar") })
    }
}

/// Only labeled fields and unambiguous dates are proposed. Users confirm every suggested field in the form.
enum ChequeOCRParser {
    static func parse(text: String, currencyCode: String, direction: ChequeDirection? = nil,
                      unsupportedArabic: Bool = false, languageCode: String = "en") -> OCRSuggestion {
        let normalized = normalizeDigits(text)
        let language = AppLanguage(rawValue: languageCode) ?? .english
        func values(_ key: String, aliases: String, acceptsCurrencyQualifier: Bool = false) -> [String] {
            let label = Localization.text(key, language: language)
            let escaped = NSRegularExpression.escapedPattern(for: label)
                .replacingOccurrences(of: "’", with: "['’]")
            return labelValues("(?:\(aliases)|\(escaped))", in: normalized, acceptsCurrencyQualifier: acceptsCurrencyQualifier)
        }
        let number = unique(values("Cheque number", aliases: #"che(?:que|ck)\h*(?:number|no\.?|#)|رقم\h*الشيك|رقم\h*شيك"#)
            .compactMap { value -> String? in
                let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard candidate.count <= 32, let digits = NumericInput.integer(candidate),
                      !digits.isEmpty else { return nil }
                return digits
            })
        let bank = unique(values("Bank", aliases: #"bank(?:\h*name)?|اسم\h*البنك|البنك"#).compactMap(cleanName))
        let payers = values("Payer", aliases: #"payer|drawer|paid\h*by|اسم\h*الساحب|اسم\h*الدافع|الساحب|الدافع"#).compactMap(cleanName)
        let payees = values("Payee", aliases: #"pay\h*to(?:\h*the\h*order\h*of)?|payee|beneficiary|اسم\h*المستفيد|المستفيد|لأمر"#).compactMap(cleanName)
        let party: String?
        switch direction {
        case .some(.incoming): party = unique(payers)
        case .some(.outgoing): party = unique(payees)
        case .none: party = unique(payers + payees)
        }
        let amountFields = values("Amount", aliases: #"amount|المبلغ(?:\h*بالأرقام|\h*بالارقام)?|القيمة"#,
                                  acceptsCurrencyQualifier: true)
        let amount = unambiguous(amountFields) { parseAmount($0, currencyCode: currencyCode, locale: language.locale) }
        let dateFields = values("Due date", aliases: #"due\h*date|maturity\h*date|تاريخ\h*الاستحقاق|تاريخ\h*الصرف|الاستحقاق"#)
        return OCRSuggestion(number: number, bank: bank, party: party, amountText: amount,
                             dueDate: unambiguous(dateFields, parse: parseDate), recognizedText: text, unsupportedArabic: unsupportedArabic)
    }

    private static func normalizeDigits(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.numericType == .decimal, let digit = scalar.properties.numericValue {
                result.append(String(Int(digit)))
                continue
            }
            switch scalar.value {
            case 0xFF0E: result.append(".")
            case 0xFF0C: result.append(",")
            case 0xFF0F: result.append("/")
            case 0x200E, 0x200F, 0x061C: break
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func labelValues(_ labels: String, in text: String, acceptsCurrencyQualifier: Bool) -> [String] {
        // A label may sit on its own line. A broad unlabeled number/date is deliberately never used.
        let qualifier = acceptsCurrencyQualifier ? #"(?:\h*\(\h*([a-z]{3})\h*\))?"# : ""
        let pattern = #"(?im)^\h*\#(labels)\#(qualifier)(?=[:：#=\s])\h*[:：#=]?\h*(?:\r?\n\h*)?([^\r\n]+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let value = Range(match.range(at: match.numberOfRanges - 1), in: text) else { return nil }
            let field = String(text[value]).trimmingCharacters(in: .whitespacesAndNewlines)
            if acceptsCurrencyQualifier, let code = Range(match.range(at: 1), in: text) {
                return "(" + String(text[code]) + ") " + field
            }
            return field
        }
    }

    private static func cleanName(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 120, cleaned.contains(where: \.isLetter) else { return nil }
        return cleaned
    }

    private static func parseAmount(_ value: String, currencyCode: String, locale: Locale) -> String? {
        let escapedCode = NSRegularExpression.escapedPattern(for: currencyCode)
        // Keep a printed code such as "(JOD):" with its value so a different currency
        // cannot be silently stripped from a labeled amount.
        let qualifier = #"(?:\(\h*\#(escapedCode)\h*\)\h*[:：#=]?\h*)?"#
        let pattern = #"^\h*\#(qualifier)(?:\#(escapedCode)\h*)?([0-9](?:[0-9.,٫٬ \u00A0\u202F'’]*[0-9])?)(?:\h*\#(escapedCode))?\h*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        var candidate = String(value[range])
        // Arabic decimal and thousands marks have distinct meanings regardless of the app language.
        let arabicMarks = candidate.contains("٫") || candidate.contains("٬")
        let decimal = arabicMarks ? "٫" : (locale.decimalSeparator ?? ".")
        var grouping = arabicMarks ? "٬" : (locale.groupingSeparator ?? ",")
        if grouping.rangeOfCharacter(from: .whitespaces) != nil {
            grouping = " "
            candidate = candidate.replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        if !arabicMarks, CurrencyMath.fractionDigits(for: currencyCode) >= 3,
           candidate.range(of: #"^[1-9][0-9]{0,2}[.,][0-9]{3}$"#, options: .regularExpression) != nil {
            return nil
        }
        let groupPattern = NSRegularExpression.escapedPattern(for: grouping)
        let decimalPattern = NSRegularExpression.escapedPattern(for: decimal)
        let format = #"^(?:[0-9]+|[1-9][0-9]{0,2}(?:\#(groupPattern)[0-9]{3})+)(?:\#(decimalPattern)[0-9]+)?$"#
        if candidate.range(of: format, options: .regularExpression) != nil {
            candidate = candidate.replacingOccurrences(of: grouping, with: "").replacingOccurrences(of: decimal, with: ".")
        } else {
            // Paper cheques can use another decimal mark. With a matching printed ISO code,
            // accept a single ungrouped decimal only. The three-digit ambiguity guard above
            // still rejects 1.250 JOD, and CurrencyMath enforces the currency's exact precision.
            guard !arabicMarks, currencyCode.range(of: #"^[A-Za-z]{3}$"#, options: .regularExpression) != nil,
                  value.range(of: currencyCode, options: .caseInsensitive) != nil,
                  candidate.range(of: #"^(?:0|[1-9][0-9]*)[.,][0-9]+$"#, options: .regularExpression) != nil else { return nil }
        }
        guard let minor = CurrencyMath.parseMinorUnits(candidate, currencyCode: currencyCode) else { return nil }
        return CurrencyMath.editable(minorUnits: minor, currencyCode: currencyCode)
    }

    private static func parseDate(_ value: String) -> LocalDay? {
        let pattern = "^\\s*([0-9]{1,4})[-/.]([0-9]{1,2})[-/.]([0-9]{1,4})\\s*$"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else { return nil }
        let parts = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }
        guard parts.count == 3 else { return nil }
        let year: Int, month: Int, day: Int
        if parts[0] >= 1000 {
            year = parts[0]
            month = parts[1]
            day = parts[2]
        }
        else if parts[2] >= 1000 {
            year = parts[2]
            if parts[0] > 12 {
                day = parts[0]
                month = parts[1]
            } else if parts[1] > 12 {
                month = parts[0]
                day = parts[1]
            } else if parts[0] == parts[1] {
                month = parts[0]
                day = parts[1]
            }
            else { return nil }
        } else { return nil }
        return LocalDay(iso: String(format: "%04d-%02d-%02d", year, month, day))
    }

    private static func unique<Value: Equatable>(_ values: [Value]) -> Value? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func unambiguous<Value: Equatable>(_ fields: [String], parse: (String) -> Value?) -> Value? {
        let parsed = fields.compactMap(parse)
        return parsed.count == fields.count ? unique(parsed) : nil
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
