import Foundation
import ShekatiCore

struct CSVImportRow: Identifiable, Sendable {
    var id: UUID { snapshot.id }
    var line: Int
    var snapshot: ChequeSnapshot
    var isProbableDuplicate: Bool
}

struct CSVImportIssue: Identifiable, Sendable {
    var id: Int { line }
    var line: Int
    var message: String
}

struct CSVImportPreview: Sendable {
    var rows: [CSVImportRow]
    var issues: [CSVImportIssue]
    var currencyCode: String
    var duplicateCount: Int { rows.filter(\.isProbableDuplicate).count }
    func payload(includeDuplicates: Bool) -> ChequeBackupPayload {
        ChequeBackupPayload(currencyCode: currencyCode,
                           records: rows.filter { includeDuplicates || !$0.isProbableDuplicate }
                            .map { ChequeBackupEntry(snapshot: $0.snapshot) })
    }
}

enum ChequeCSV {
    static let header = ["direction", "status", "amount", "currency", "due_date", "number", "bank", "branch",
                         "party", "account_reference", "issue_date", "actual_date", "notes", "_format"]

    static func export(_ cheques: [ChequeSnapshot]) -> Data {
        var lines = [header.map(quote).joined(separator: ",")]
        for cheque in cheques {
            // Mark our escaping explicitly so a round trip removes exactly one prefix.
            // Numbers and references are text, never Excel formulas or numeric cells.
            let text = [cheque.number, cheque.bank, cheque.branch, cheque.party, cheque.accountReference, cheque.notes]
                .map { "'" + $0 }
            let values = [cheque.direction.rawValue, cheque.status.rawValue,
                          CurrencyMath.editable(minorUnits: cheque.amountMinorUnits, currencyCode: cheque.currencyCode),
                          cheque.currencyCode, cheque.dueDate.iso, text[0], text[1], text[2], text[3], text[4],
                          cheque.issueDate?.iso ?? "", cheque.actualDate?.iso ?? "", text[5], "shekati-v1"]
            lines.append(values.map(quote).joined(separator: ","))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func template(currencyCode: String) -> Data {
        let snapshot = ChequeSnapshot(direction: .outgoing, amountMinorUnits: 100 * Int64(pow(10.0, Double(CurrencyMath.fractionDigits(for: currencyCode)))),
                                      currencyCode: currencyCode, dueDate: .today.adding(days: 7),
                                      number: "000001", bank: "Demo bank", party: "Demo payee")
        return export([snapshot])
    }

    static func preview(_ data: Data, currencyCode: String, existing: [ChequeSnapshot]) throws -> CSVImportPreview {
        guard data.count <= 10_000_000, let decoded = String(data: data, encoding: .utf8),
              Locale.commonISOCurrencyCodes.contains(currencyCode) else { throw ChequeTransferError.invalidFile }
        let text = decoded.hasPrefix("\u{FEFF}") ? String(decoded.dropFirst()) : decoded
        let cells = try parse(text)
        guard let first = cells.first, cells.count <= 5_001 else { throw ChequeTransferError.invalidFile }
        let columns = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(columns).count == columns.count,
              ["direction", "amount", "due_date"].allSatisfy(columns.contains) else {
            throw ChequeTransferError.invalidRecords
        }
        let indices = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        var accepted: [CSVImportRow] = []
        var issues: [CSVImportIssue] = []
        var buckets = Dictionary(grouping: existing, by: duplicateBucket)
        let baseRank = existing.map(\.manualRank).max() ?? -1
        for (offset, values) in cells.dropFirst().enumerated() {
            if values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            let line = offset + 2
            guard values.count == columns.count else {
                issues.append(CSVImportIssue(line: line, message: "The number of columns does not match the header.")); continue
            }
            func raw(_ name: String) -> String { indices[name].map { values[$0] } ?? "" }
            let ownFile = raw("_format") == "shekati-v1"
            func field(_ name: String) -> String {
                let value = raw(name)
                return ownFile && value.hasPrefix("'") ? String(value.dropFirst()) : value
            }
            let code = raw("currency").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard code.isEmpty || code == currencyCode else {
                issues.append(CSVImportIssue(line: line, message: "The file currency differs from your saved cheques.")); continue
            }
            let direction = parseDirection(raw("direction"))
            let status = raw("status").isEmpty ? ChequeStatus.pending : parseStatus(raw("status"))
            guard let direction, let status,
                  let amount = CurrencyMath.parseMinorUnits(raw("amount"), currencyCode: currencyCode),
                  let due = LocalDay(iso: raw("due_date")) else {
                issues.append(CSVImportIssue(line: line, message: "Use incoming or outgoing, a positive amount and a valid YYYY-MM-DD date.")); continue
            }
            let issue = raw("issue_date").isEmpty ? nil : LocalDay(iso: raw("issue_date"))
            let actual = raw("actual_date").isEmpty ? nil : LocalDay(iso: raw("actual_date"))
            guard (raw("issue_date").isEmpty || issue != nil), (raw("actual_date").isEmpty || actual != nil),
                  status != .settled || actual != nil else {
                issues.append(CSVImportIssue(line: line, message: "Settled cheques need an actual date. Dates must use YYYY-MM-DD.")); continue
            }
            guard issue.map({ $0 <= due }) ?? true,
                  issue.flatMap({ issued in actual.map { $0 >= issued } }) ?? true else {
                issues.append(CSVImportIssue(line: line, message: "Issue date must not be after the due date or actual settlement date.")); continue
            }
            let nextRank = baseRank.addingReportingOverflow(Int64(offset + 1))
            guard !nextRank.overflow else { throw ChequeTransferError.invalidRecords }
            let snapshot = ChequeSnapshot(direction: direction, status: status, amountMinorUnits: amount,
                                          currencyCode: currencyCode, dueDate: due, actualDate: actual, issueDate: issue,
                                          number: field("number"), bank: field("bank"), branch: field("branch"),
                                          party: field("party"), accountReference: field("account_reference"),
                                          notes: field("notes"), manualRank: nextRank.partialValue)
            let bucket = duplicateBucket(snapshot)
            let duplicate = hasDuplicate(snapshot, candidates: buckets[bucket] ?? [])
            accepted.append(CSVImportRow(line: line, snapshot: snapshot, isProbableDuplicate: duplicate))
            buckets[bucket, default: []].append(snapshot)
        }
        let preview = CSVImportPreview(rows: accepted, issues: issues, currencyCode: currencyCode)
        try preview.payload(includeDuplicates: true).validate()
        return preview
    }

    static func duplicateIDs(for snapshots: [ChequeSnapshot], existing: [ChequeSnapshot]) -> Set<UUID> {
        let buckets = Dictionary(grouping: existing, by: duplicateBucket)
        return Set(snapshots.filter { hasDuplicate($0, candidates: buckets[duplicateBucket($0)] ?? []) }.map(\.id))
    }

    private static func duplicateBucket(_ cheque: ChequeSnapshot) -> String {
        let number = ChequeEntryAssistance.normalized(cheque.number)
        let prefix = "\(cheque.direction.rawValue)|\(cheque.currencyCode)|"
        if !number.isEmpty { return prefix + "number:" + number }
        return prefix + "identity:\(cheque.amountMinorUnits)|\(cheque.dueDate.iso)|" + ChequeEntryAssistance.normalized(cheque.party)
    }
    private static func hasDuplicate(_ cheque: ChequeSnapshot, candidates: [ChequeSnapshot]) -> Bool {
        if ChequeEntryAssistance.normalized(cheque.number).isEmpty && ChequeEntryAssistance.normalized(cheque.party).isEmpty { return false }
        // Stop on the first match. The helper remains the single matching policy.
        return candidates.contains { !ChequeEntryAssistance.probableDuplicateIDs(for: cheque, among: [$0]).isEmpty }
    }

    private static func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private static func parseDirection(_ value: String) -> ChequeDirection? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "incoming", "وارد": return .incoming
        case "outgoing", "صادر": return .outgoing
        default: return nil
        }
    }
    private static func parseStatus(_ value: String) -> ChequeStatus? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "معلق", "معلّق": return .pending
        case "settled", "paid", "collected", "تم الصرف", "تم التحصيل": return .settled
        case "returned", "مرتجع": return .returned
        case "cancelled", "ملغى": return .cancelled
        default: return nil
        }
    }

    // RFC 4180 quoting, including escaped quotes and embedded CR/LF, without lossy splitting.
    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(character) }
            } else if character == "," {
                row.append(field); field = ""; closedQuote = false
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                row.append(field); rows.append(row); row = []; field = ""; closedQuote = false
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
            } else if character == "\"", field.isEmpty && !closedQuote {
                quoted = true
            } else {
                guard !closedQuote && character != "\"" else { throw ChequeTransferError.invalidFile }
                field.append(character)
            }
            guard rows.count <= 5_001, row.count <= 100, field.utf8.count <= 100_000 else { throw ChequeTransferError.invalidFile }
            index += 1
        }
        guard !quoted else { throw ChequeTransferError.invalidFile }
        if !field.isEmpty || !row.isEmpty || closedQuote { row.append(field); rows.append(row) }
        return rows
    }
}
