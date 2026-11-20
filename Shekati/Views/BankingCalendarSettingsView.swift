import SwiftUI
import ShekatiCore

struct BankingCalendarSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var holiday = Date()
    var body: some View {
        @Bindable var prefs = app.preferences
        let locale = prefs.language.locale
        let region = Binding<String>(get: { prefs.bankingCalendar.region }, set: { value in
            prefs.bankingCalendar.region = value
            prefs.bankingCalendar.closedWeekdays = BankingCalendar.defaultWeekends(in: value)
        })
        Form {
            Section {
                Picker(app.tr("Bank region"), selection: region) {
                    ForEach(Locale.Region.isoRegions.map(\.identifier).sorted(), id: \.self) { code in
                        Text(locale.localizedString(forRegionCode: code) ?? code).tag(code)
                    }
                }
                Picker(app.tr("Time zone"), selection: $prefs.bankingCalendar.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                Toggle(app.tr("Move reminders to the preceding banking day"), isOn: $prefs.bankingCalendar.shiftsReminders)
            }
            if prefs.bankingCalendar.shiftsReminders {
                Section(app.tr("Weekly closing days")) {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(weekdayName(day), isOn: Binding(get: { prefs.bankingCalendar.closedWeekdays.contains(day) }, set: { closed in
                            if closed && prefs.bankingCalendar.closedWeekdays.count < 6 { prefs.bankingCalendar.closedWeekdays.insert(day) }
                            if !closed { prefs.bankingCalendar.closedWeekdays.remove(day) }
                        }))
                    }
                }
                Section(app.tr("Bank holidays")) {
                    DatePicker(app.tr("Holiday"), selection: $holiday, displayedComponents: .date)
                    Button(app.tr("Add holiday")) { prefs.bankingCalendar.holidays.insert(LocalDay(date: holiday).iso) }
                    ForEach(prefs.bankingCalendar.holidays.sorted(), id: \.self) { day in
                        HStack {
                            Text(day)
                            Spacer()
                            Button(role: .destructive) { prefs.bankingCalendar.holidays.remove(day) } label: {
                                Image(systemName: "trash").accessibilityLabel(app.tr("Delete"))
                            }
                        }
                    }
                }
            }
        }.navigationTitle(app.tr("Banking calendar"))
    }
    private func weekdayName(_ day: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = app.preferences.language.locale
        return formatter.weekdaySymbols[day - 1]
    }
}

