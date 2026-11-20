import Foundation
import SwiftData
import ShekatiCore

enum BankingError: String, LocalizedError {
    case invalid = "Check the amount, date and selected account."
    case unavailable = "This action is unavailable for the current cheque."
    case conflict = "Review the conflicting entries before continuing."
    case accountRequired = "Select a bank account in the cheque currency."
    case paidFeature = "This action requires Shekati Plus."
    case limit = "The free plan includes one bank account."
    case chequeLimit = "The free plan includes ten active cheques."
    case missing = "Some financial records are still syncing."
    case staleBalance = "The balance changed. Review the new difference before confirming."
    var errorDescription: String? { rawValue }
}

@MainActor
enum BankingLedger {
    static func position(for record: ChequeRecord, events: [LedgerEventRecord]) -> ChequePosition {
        position(for: record, operations: events.filter { $0.chequeID == record.id }.compactMap(\.operation))
    }

    private static func position(for record: ChequeRecord, operations: [LedgerOperation]) -> ChequePosition {
        let baseline = record.ledgerBaselineStatusRaw.flatMap(PaperState.init(rawValue:))
            ?? PaperState.initial(record.status, direction: record.direction)
        return ChequePosition(original: record.amountMinorUnits, direction: record.direction, baseline: baseline,
                              currency: record.currencyCode, operations: operations)
    }

    /// Inactive replacement branches stay available to the history view while the active
    /// register, quota, calendar and notifications use only the accepted lineage.
    static func effectivePositions(records: [ChequeRecord], events: [LedgerEventRecord]) -> [UUID: ChequePosition] {
        let groups = Dictionary(grouping: records, by: \.id)
        let eventGroups = Dictionary(grouping: events, by: \.chequeID)
        var positions: [UUID: ChequePosition] = [:]
        var unresolved = [UUID: [ChequeRecord]]()
        var queue = [ChequeRecord]()
        for group in groups.values where group.count == 1 {
            let record = group[0]
            if let parentID = record.replacesChequeID { unresolved[parentID, default: []].append(record) }
            else { queue.append(record) }
        }
        while let record = queue.popLast() {
            let current = position(for: record, events: eventGroups[record.id] ?? [])
            positions[record.id] = current
            if current.conflicts.isEmpty, let child = current.replacementID,
               let replacement = unresolved[record.id]?.first(where: { $0.id == child }) {
                queue.append(replacement)
            }
        }
        return positions
    }

    static func reminderInputs(records: [ChequeRecord], events: [LedgerEventRecord]) -> [ChequeReminderInput] {
        let effective = effectivePositions(records: records, events: events)
        return records.compactMap { record in
            guard record.isActive, let position = effective[record.id], position.conflicts.isEmpty,
                  [.inHand, .deposited, .issued, .returned, .lost].contains(position.state), position.remaining > 0 else { return nil }
            var snapshot = record.snapshot
            snapshot.status = position.legacyStatus
            snapshot.amountMinorUnits = position.remaining
            return ChequeReminderInput(snapshot: snapshot, enabled: record.remindersEnabled,
                                       offsets: record.reminderOffsets, hour: record.reminderHour, minute: record.reminderMinute)
        }
    }

    static func addAccount(name: String, currency: String, opening: Int64, isPlus: Bool, context: ModelContext) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, Locale.commonISOCurrencyCodes.contains(currency) else { throw BankingError.invalid }
        if !isPlus, try context.fetchCount(FetchDescriptor<BankAccountRecord>()) >= 1 { throw BankingError.limit }
        let account = BankAccountRecord(name: clean, currencyCode: currency, openingMinor: opening)
        context.insert(account)
        context.insert(ChequeBookRecord(accountID: account.id, name: clean))
        try save(context)
    }

    static func link(record: ChequeRecord, account: BankAccountRecord, book: ChequeBookRecord?, context: ModelContext) throws {
        guard record.isActive, record.bankAccountID == nil, account.currencyCode == record.currencyCode,
              record.direction != .outgoing || book?.accountID == account.id else { throw BankingError.invalid }
        record.bankAccountID = account.id
        record.chequeBookID = book?.id
        try save(context)
    }

    static func perform(_ action: LedgerAction, for record: ChequeRecord, amount: Int64 = 0, day: LocalDay,
                        party: String = "", replacementNumber: String = "", replacementDue: LocalDay? = nil,
                        expectedParent: UUID?, isPlus: Bool, context: ModelContext) throws {
        guard !action.isPremium || isPlus else { throw BankingError.paidFeature }
        guard record.isActive, day <= .today, record.issueDate.map({ day >= $0 }) ?? true else { throw BankingError.invalid }
        let all = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let current = position(for: record, events: all)
        guard current.conflicts.isEmpty, expectedParent == current.accepted.last?.id else { throw BankingError.conflict }
        guard current.allowed.contains(action) else { throw BankingError.unavailable }
        guard let accountID = record.bankAccountID,
              let account = try context.fetch(FetchDescriptor<BankAccountRecord>()).first(where: { $0.id == accountID }),
              account.currencyCode == record.currencyCode else { throw BankingError.accountRequired }
        if let ancestor = record.replacesChequeID {
            guard let original = try context.fetch(FetchDescriptor<ChequeRecord>()).first(where: { $0.id == ancestor }),
                  position(for: original, events: all).replacementID == record.id else { throw BankingError.conflict }
        }
        let baseline = record.ledgerBaselineStatusRaw ?? PaperState.initial(record.status, direction: record.direction).rawValue
        let successorID: UUID? = action == .replace ? UUID() : nil
        let quantity = [.settle, .replace, .acknowledgeEndorsement].contains(action) ? current.remaining : amount
        let op = LedgerOperation(parentID: expectedParent, chequeID: record.id, accountID: accountID,
                                 kind: action, day: day, amount: quantity, party: party,
                                 relatedID: successorID, currency: account.currencyCode)
        let projected = position(for: record, operations: all.filter { $0.chequeID == record.id }.compactMap(\.operation) + [op])
        guard projected.accepted.last?.id == op.id, projected.conflicts.isEmpty else { throw BankingError.invalid }

        if let successorID {
            let number = replacementNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty, number != record.number, let replacementDue, replacementDue >= day else { throw BankingError.invalid }
            let existing = try context.fetch(FetchDescriptor<ChequeRecord>())
            guard !existing.contains(where: { $0.isActive && $0.bankAccountID == accountID && $0.number == number
                && $0.direction == record.direction }) else { throw BankingError.invalid }
            var successor = record.snapshot
            successor.id = successorID; successor.amountMinorUnits = current.remaining; successor.status = .pending
            successor.number = number; successor.dueDate = replacementDue; successor.createdAt = Date()
            successor.issueDate = day; successor.actualDate = nil
            let replacement = ChequeRecord(snapshot: successor, remindersEnabled: record.remindersEnabled,
                                           reminderOffsets: record.reminderOffsets, reminderHour: record.reminderHour,
                                           reminderMinute: record.reminderMinute)
            replacement.bankAccountID = accountID; replacement.chequeBookID = record.chequeBookID
            replacement.replacesChequeID = record.id
            context.insert(replacement)
        }
        record.ledgerBaselineStatusRaw = baseline
        context.insert(LedgerEventRecord(op))
        reflect(projected, record: record)
        try save(context)
    }

    static func dismissConflict(_ op: LedgerOperation, reason: String, record: ChequeRecord,
                                context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let position = self.position(for: record, events: all)
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, (position.conflicts.contains(op) || position.accepted.last?.id == op.id),
              op.chequeID == record.id else { throw BankingError.invalid }
        if op.kind == .replace, let child = op.relatedID {
            guard !all.contains(where: { $0.chequeID == child }) else { throw BankingError.unavailable }
        }
        let correction = LedgerOperation(chequeID: record.id, accountID: record.bankAccountID, kind: .discardConflict,
                                         day: .today, party: reason, relatedID: op.id, currency: record.currencyCode)
        let event = LedgerEventRecord(correction)
        context.insert(event)
        reflect(self.position(for: record, events: all + [event]), record: record)
        try save(context)
    }

    static func reflect(_ projection: ChequePosition, record: ChequeRecord) {
        record.status = projection.legacyStatus
        record.actualDate = projection.state == .settled ? projection.accepted.last?.day : nil
    }

    static func adjustments(account: BankAccountRecord, events: [LedgerEventRecord]) throws -> [LedgerOperation] {
        let raw = events.filter { $0.accountID == account.id && $0.chequeID == nil }
        let decoded = raw.compactMap(\.operation)
        guard decoded.count == raw.count else { throw BankingError.missing }
        var ignored = Set(decoded.filter { $0.kind == .discardConflict }.compactMap(\.relatedID))
        let children = Dictionary(grouping: decoded.filter { $0.kind == .reconcile }, by: \.parentID)
        var obsolete = Array(ignored)
        while let parent = obsolete.popLast() {
            for child in children[parent] ?? [] where ignored.insert(child.id).inserted { obsolete.append(child.id) }
        }
        let candidates = Dictionary(grouping: decoded.filter { $0.kind == .reconcile && !ignored.contains($0.id) }, by: \.id)
        guard candidates.values.allSatisfy({ group in group.allSatisfy { $0 == group[0] } }) else { throw BankingError.conflict }
        var result: [LedgerOperation] = []
        let byParent = Dictionary(grouping: candidates.values.compactMap(\.first), by: \.parentID)
        var next = byParent[nil] ?? []
        while !next.isEmpty {
            guard next.count == 1, let op = next.first, op.currency == account.currencyCode,
                  result.count < candidates.count else { throw BankingError.conflict }
            result.append(op)
            next = byParent[op.id] ?? []
        }
        guard result.count == candidates.count else { throw BankingError.conflict }
        return result
    }

    static func reconciliationConflicts(account: BankAccountRecord, events: [LedgerEventRecord]) -> [LedgerOperation] {
        let data = events.filter { $0.accountID == account.id && $0.chequeID == nil }.compactMap(\.operation)
        let ignored = Set(data.filter { $0.kind == .discardConflict }.compactMap(\.relatedID))
        let candidates = data.filter { $0.kind == .reconcile && !ignored.contains($0.id) }
        let groups = Dictionary(grouping: candidates, by: \.parentID)
        var parent: UUID?
        var seen = Set<UUID>()
        while let siblings = groups[parent], let first = siblings.first {
            let ids = Set(siblings.map(\.id))
            if ids.count > 1 { return siblings.filter { seen.insert($0.id).inserted } }
            guard seen.insert(first.id).inserted else { break }
            parent = first.id
        }
        return []
    }

    static func discardAdjustment(_ op: LedgerOperation, reason: String, account: BankAccountRecord, context: ModelContext) throws {
        let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, reconciliationConflicts(account: account, events: events).contains(op) else { throw BankingError.invalid }
        context.insert(LedgerEventRecord(LedgerOperation(chequeID: nil, accountID: account.id, kind: .discardConflict,
                       day: .today, party: note, relatedID: op.id, currency: account.currencyCode)))
        try save(context)
    }

    static func outlook(account: BankAccountRecord, records: [ChequeRecord], events: [LedgerEventRecord],
                        today: LocalDay, horizon: Int = 60) throws -> AccountOutlook {
        let raw = events.filter { $0.accountID == account.id }
        guard raw.allSatisfy({ $0.operation != nil }) else { throw BankingError.missing }
        let eventGroups = Dictionary(grouping: events.compactMap(\.operation), by: \.chequeID)
        let byID = Dictionary(grouping: records, by: \.id)
        let linked = records.filter { $0.bankAccountID == account.id }
        guard linked.allSatisfy({ byID[$0.id]?.count == 1 && $0.currencyCode == account.currencyCode }),
              raw.compactMap(\.chequeID).allSatisfy({ byID[$0]?.first?.bankAccountID == account.id }) else { throw BankingError.missing }
        var movements = try adjustments(account: account, events: events).map(\.amount)
        var items: [TreasuryItem] = []
        for record in linked {
            let position = position(for: record, operations: eventGroups[record.id] ?? [])
            guard position.conflicts.isEmpty else { throw BankingError.conflict }
            if let ancestorID = record.replacesChequeID {
                guard let parent = byID[ancestorID]?.first else { throw BankingError.missing }
                let previous = self.position(for: parent, operations: eventGroups[ancestorID] ?? [])
                guard previous.conflicts.isEmpty else { throw BankingError.conflict }
                if previous.replacementID != record.id { continue }
            }
            if let replacementID = position.replacementID, byID[replacementID]?.first == nil { throw BankingError.missing }
            movements.append(contentsOf: position.bankMovements.values)
            if record.isActive {
                items.append(TreasuryItem(id: record.id, due: record.dueDate, direction: record.direction,
                                          state: position.state, remaining: position.remaining))
            }
        }
        return try AccountOutlook(opening: account.openingMinor, movements: movements, items: items, today: today, horizon: horizon)
    }

    static func reconcile(_ account: BankAccountRecord, statement: Int64, expected: Int64, day: LocalDay = .today, reason: String = "", context: ModelContext) throws {
        guard day <= .today else { throw BankingError.invalid }
        let records = try context.fetch(FetchDescriptor<ChequeRecord>())
        let events = try context.fetch(FetchDescriptor<LedgerEventRecord>())
        let current = try outlook(account: account, records: records, events: events, today: .today).recorded
        guard current == expected else { throw BankingError.staleBalance }
        let delta = statement.subtractingReportingOverflow(current)
        guard !delta.overflow else { throw TreasuryError.overflow }
        let parent = try adjustments(account: account, events: events).last?.id
        let operation = LedgerOperation(parentID: parent, chequeID: nil, accountID: account.id, kind: .reconcile,
                                       day: day, amount: delta.partialValue, party: reason.trimmingCharacters(in: .whitespacesAndNewlines), currency: account.currencyCode)
        context.insert(LedgerEventRecord(operation))
        try save(context)
    }

    static func signedAmount(_ text: String, currency: String) -> Int64? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = raw.hasPrefix("-") || raw.hasPrefix("−")
        if negative { raw.removeFirst() }
        let normalized = NumericInput.latinDigits(raw).replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".")
        if let value = CurrencyMath.parseMinorUnits(normalized, currencyCode: currency) { return negative ? -value : value }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty, parts[0].allSatisfy({ $0 == "0" }),
              parts.count == 1 || (!parts[1].isEmpty && parts[1].count <= CurrencyMath.fractionDigits(for: currency)
                                    && parts[1].allSatisfy({ $0 == "0" })) else { return nil }
        return 0
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
