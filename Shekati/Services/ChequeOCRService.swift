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
    static func recognize(image: UIImage, currencyCode: String, direction: ChequeDirection? = nil) async throws -> OCRSuggestion {
        guard let cgImage = image.cgImage else { throw OCRRecognitionError.invalidImage }
        let orientation = image.imageOrientation.cgOrientation
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let supported = try request.supportedRecognitionLanguages()
            let arabic = supported.filter { $0.lowercased().hasPrefix("ar") }
            let english = supported.filter { $0.lowercased().hasPrefix("en") }
            let selected = arabic + Array(english.prefix(1))
            if !selected.isEmpty { request.recognitionLanguages = Array(selected) }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? []).sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRRecognitionError.noText }
            return ChequeOCRParser.parse(text: text, currencyCode: currencyCode, direction: direction, unsupportedArabic: arabic.isEmpty)
        }.value
    }
}

/// Only labeled fields and unambiguous dates are proposed. Users confirm every suggested field in the form.
enum ChequeOCRParser {
    static func parse(text: String, currencyCode: String, direction: ChequeDirection? = nil,
                      unsupportedArabic: Bool = false) -> OCRSuggestion {
        let normalized = normalizeDigits(text)
        let number = unique(labelValues("(?:che(?:que|ck)\\s*(?:number|no\\.?|#)|رقم\\s*الشيك|رقم\\s*شيك)", in: normalized)
            .compactMap { value -> String? in
                let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard candidate.count <= 32, let digits = NumericInput.integer(candidate),
                      !digits.isEmpty else { return nil }
                return digits
            })
        let bank = unique(labelValues("(?:bank(?:\\s*name)?|اسم\\s*البنك|البنك)", in: normalized).compactMap(cleanName))
        let payers = labelValues("(?:payer|drawer|paid\\s*by|اسم\\s*الساحب|اسم\\s*الدافع|الساحب|الدافع)", in: normalized).compactMap(cleanName)
        let payees = labelValues("(?:pay\\s*to(?:\\s*the\\s*order\\s*of)?|payee|beneficiary|اسم\\s*المستفيد|المستفيد|لأمر)", in: normalized).compactMap(cleanName)
        let party: String?
        switch direction {
        case .some(.incoming): party = unique(payers)
        case .some(.outgoing): party = unique(payees)
        case .none: party = unique(payers + payees)
        }
        let amounts = labelValues("(?:amount(?:\\s*\\([A-Z]{3}\\))?|المبلغ(?:\\s*بالأرقام|\\s*بالارقام)?|القيمة)", in: normalized)
            .compactMap { parseAmount($0, currencyCode: currencyCode) }
        let dates = labelValues("(?:due\\s*date|maturity\\s*date|تاريخ\\s*الاستحقاق|تاريخ\\s*الصرف|الاستحقاق)", in: normalized)
            .compactMap(parseDate)
        return OCRSuggestion(number: number, bank: bank, party: party, amountText: unique(amounts),
                             dueDate: unique(dates), recognizedText: text, unsupportedArabic: unsupportedArabic)
    }

    private static func normalizeDigits(_ text: String) -> String {
        var result = ""
        for scalar in NumericInput.latinDigits(text).unicodeScalars {
            switch scalar.value {
            case 0x066B: result.append(".")
            case 0x066C: result.append(",")
            case 0x200E, 0x200F, 0x061C: break
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func labelValues(_ labels: String, in text: String) -> [String] {
        // A label may sit on its own line. A broad unlabeled number/date is deliberately never used.
        let pattern = "(?im)^\\s*\(labels)\\s*(?:[:：#=-]\\s*)?(?:\\n\\s*)?([^\\r\\n]+)$"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let value = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[value]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func cleanName(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 120, cleaned.contains(where: \.isLetter) else { return nil }
        return cleaned
    }

    private static func parseAmount(_ value: String, currencyCode: String) -> String? {
        // Accept conventional comma grouping; never turn European 1.250,50 into a different amount.
        let escapedCode = NSRegularExpression.escapedPattern(for: currencyCode)
        let pattern = "^\\s*(?:\(escapedCode)\\s*)?([0-9]+(?:[.,][0-9]+)*)(?:\\s*\(escapedCode))?\\s*$"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        var candidate = String(value[range])
        if candidate.contains(",") {
            if !candidate.contains("."), candidate.filter({ $0 == "," }).count == 1,
               let fraction = candidate.split(separator: ",").last,
               fraction.count <= CurrencyMath.fractionDigits(for: currencyCode) {
                // For a three-decimal currency, 1,250 could mean 1.250 or 1250; require manual confirmation.
                return nil
            }
            guard candidate.range(of: "^[0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
            candidate.removeAll { $0 == "," }
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
