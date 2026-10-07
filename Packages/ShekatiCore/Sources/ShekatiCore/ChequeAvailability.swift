import Foundation

/// Days with no outstanding outgoing cheque due. The caller excludes deleted records.
/// The inclusive date range is bounded so UI requests have predictable work and memory.
public struct ChequeAvailability: Equatable, Sendable {
    public static let maxDayCount = 366
    public let freeDays: [LocalDay]
    public let isValidRange: Bool

    public init(cheques: [ChequeSnapshot], from: LocalDay, through: LocalDay) {
        guard from <= through else {
            freeDays = []
            isValidRange = false
            return
        }

        var days: [LocalDay] = []
        var day = from
        for _ in 0..<Self.maxDayCount {
            days.append(day)
            if day == through { break }
            let next = day.adding(days: 1)
            guard next > day else { break }
            day = next
        }
        guard days.last == through else {
            freeDays = []
            isValidRange = false
            return
        }

        let occupied = Set(cheques.lazy.filter {
            $0.direction == .outgoing && $0.isOutstanding && $0.dueDate >= from && $0.dueDate <= through
        }.map(\.dueDate))
        freeDays = days.filter { !occupied.contains($0) }
        isValidRange = true
    }
}
