import Foundation
import Observation
import ShekatiCore

struct AppLanguage: RawRepresentable, Hashable, CaseIterable, Identifiable, Sendable {
    static let supported = "ar bn ca zh-Hans zh-Hant hr cs da nl en-AU en-CA en-GB en en-US fi fr fr-CA de el gu he hi hu id it ja kn ko ms ml mr nb or pl pt-BR pt-PT pa ro ru sk sl es-MX es-ES sv ta te th tr uk ur vi".split(separator: " ").map(String.init)
    let rawValue: String
    init?(rawValue: String) {
        guard Self.supported.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }
    static let arabic = Self(rawValue: "ar")!
    static let english = Self(rawValue: "en")!
    static let allCases = supported.filter { $0 != "en" }.compactMap(Self.init(rawValue:))
    static var preferred: Self {
        let best = Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages).first
        return best.flatMap(Self.init(rawValue:)) ?? .english
    }
    var id: String { rawValue }
    var isRTL: Bool { ["ar", "he", "ur"].contains(rawValue) }
    var locale: Locale { Locale(identifier: rawValue + "@numbers=latn") }
    var displayName: String { locale.localizedString(forIdentifier: rawValue) ?? rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum ChequeListScope: String, CaseIterable, Identifiable {
    case outstanding, allRecords
    var id: String { rawValue }
}

@MainActor @Observable
final class UserPreferences {
    private let defaults: UserDefaults
    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    var bankingCalendar: BankingCalendar {
        didSet { if let data = try? JSONEncoder().encode(bankingCalendar) { defaults.set(data, forKey: "bankingCalendar.v1") } }
    }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var sort: ChequeSort { didSet { defaults.set(sort.rawValue, forKey: "sort") } }
    var ascending: Bool { didSet { defaults.set(ascending, forKey: "ascending") } }
    var chequeListScope: ChequeListScope { didSet { defaults.set(chequeListScope.rawValue, forKey: "chequeListScope") } }
    var reminderOffsets: [Int] { didSet { defaults.set(reminderOffsets, forKey: "reminderOffsets") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: "reminderMinute") } }
    var dailySummary: Bool { didSet { defaults.set(dailySummary, forKey: "dailySummary") } }
    var hideNotificationDetails: Bool { didSet { defaults.set(hideNotificationDetails, forKey: "hideNotificationDetails") } }
    var appLockEnabled: Bool { didSet { defaults.set(appLockEnabled, forKey: "appLockEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var localCalendar = BankingCalendar()
        localCalendar.closedWeekdays = BankingCalendar.defaultWeekends(in: localCalendar.region)
        bankingCalendar = defaults.data(forKey: "bankingCalendar.v1").flatMap { try? JSONDecoder().decode(BankingCalendar.self, from: $0) } ?? localCalendar
        let preferred = AppLanguage.preferred
        language = defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? preferred
        appearance = defaults.string(forKey: "appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
        sort = defaults.string(forKey: "sort").flatMap(ChequeSort.init(rawValue:)) ?? .dueDate
        ascending = (defaults.object(forKey: "ascending") as? Bool) ?? true
        chequeListScope = defaults.string(forKey: "chequeListScope").flatMap(ChequeListScope.init(rawValue:)) ?? .outstanding
        reminderOffsets = defaults.array(forKey: "reminderOffsets") as? [Int] ?? [3, 1, 0]
        reminderHour = (defaults.object(forKey: "reminderHour") as? Int) ?? 9
        reminderMinute = (defaults.object(forKey: "reminderMinute") as? Int) ?? 0
        dailySummary = defaults.bool(forKey: "dailySummary")
        hideNotificationDetails = defaults.bool(forKey: "hideNotificationDetails")
        appLockEnabled = defaults.bool(forKey: "appLockEnabled")
    }

    var notificationSignature: String {
        "\(language.rawValue)|\(reminderOffsets.sorted())|\(reminderHour):\(reminderMinute)|\(dailySummary)|\(hideNotificationDetails)|\(bankingCalendar.shiftsReminders)|\(bankingCalendar.timeZoneID)|\(bankingCalendar.closedWeekdays.sorted())|\(bankingCalendar.holidays.sorted())"
    }

    func tr(_ key: String) -> String { Localization.text(key, language: language) }
}
