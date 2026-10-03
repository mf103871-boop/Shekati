import Foundation

/// A Gregorian civil day. Its identity never contains a time or a time zone.
public struct LocalDay: Codable, Hashable, Comparable, Sendable {
    private let year: Int
    private let month: Int
    private let day: Int

    public init(date: Date, calendar: Calendar = .current) {
        let components = Self.gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let parsedYear = Int(iso.prefix(4)),
              let parsedMonth = Int(iso.dropFirst(5).prefix(2)),
              let parsedDay = Int(iso.suffix(2)), (1...9999).contains(parsedYear) else { return nil }
        let utc = Self.gregorian(in: TimeZone(secondsFromGMT: 0)!)
        guard let value = utc.date(from: DateComponents(year: parsedYear, month: parsedMonth, day: parsedDay, hour: 12)) else { return nil }
        let verified = utc.dateComponents([.year, .month, .day], from: value)
        guard verified.year == parsedYear, verified.month == parsedMonth, verified.day == parsedDay else { return nil }
        year = parsedYear
        month = parsedMonth
        day = parsedDay
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public func date(calendar: Calendar = .current) -> Date {
        let civil = Self.gregorian(in: calendar.timeZone)
        // Noon exists across ordinary daylight-saving transitions; startOfDay handles missing midnight.
        let noon = civil.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return civil.startOfDay(for: noon)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        // Add civil days in UTC so date arithmetic never skips a date after a historical zone change.
        // The calendar argument is retained for source compatibility; only Date conversion uses its zone.
        let civil = Self.gregorian(in: TimeZone(secondsFromGMT: 0)!)
        let noon = civil.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        guard let result = civil.date(byAdding: .day, value: days, to: noon) else { return self }
        return LocalDay(date: result, calendar: civil)
    }

    public static var today: LocalDay { LocalDay(date: Date()) }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let day = LocalDay(iso: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Gregorian YYYY-MM-DD")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    private static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
