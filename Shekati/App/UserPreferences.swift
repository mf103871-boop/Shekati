import Foundation
import Observation
import ShekatiCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue == "ar" ? "ar" : "en") }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

@MainActor @Observable
final class UserPreferences {
    private let defaults: UserDefaults
    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var sort: ChequeSort { didSet { defaults.set(sort.rawValue, forKey: "sort") } }
    var ascending: Bool { didSet { defaults.set(ascending, forKey: "ascending") } }
    var reminderOffsets: [Int] { didSet { defaults.set(reminderOffsets, forKey: "reminderOffsets") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: "reminderMinute") } }
    var dailySummary: Bool { didSet { defaults.set(dailySummary, forKey: "dailySummary") } }
    var hideNotificationDetails: Bool { didSet { defaults.set(hideNotificationDetails, forKey: "hideNotificationDetails") } }
    var appLockEnabled: Bool { didSet { defaults.set(appLockEnabled, forKey: "appLockEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferred = Locale.preferredLanguages.first?.hasPrefix("ar") == true ? AppLanguage.arabic : .english
        language = defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? preferred
        appearance = defaults.string(forKey: "appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
        sort = defaults.string(forKey: "sort").flatMap(ChequeSort.init(rawValue:)) ?? .dueDate
        ascending = (defaults.object(forKey: "ascending") as? Bool) ?? true
        reminderOffsets = defaults.array(forKey: "reminderOffsets") as? [Int] ?? [3, 1, 0]
        reminderHour = (defaults.object(forKey: "reminderHour") as? Int) ?? 9
        reminderMinute = (defaults.object(forKey: "reminderMinute") as? Int) ?? 0
        dailySummary = defaults.bool(forKey: "dailySummary")
        hideNotificationDetails = defaults.bool(forKey: "hideNotificationDetails")
        appLockEnabled = defaults.bool(forKey: "appLockEnabled")
    }

    var notificationSignature: String {
        "\(language.rawValue)|\(reminderOffsets.sorted())|\(reminderHour):\(reminderMinute)|\(dailySummary)|\(hideNotificationDetails)"
    }

    func tr(_ key: String) -> String { Localization.text(key, language: language) }
}
