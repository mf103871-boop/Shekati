import SwiftUI
import ShekatiCore

extension Binding where Value == String {
    /// Shows Western digit glyphs without rewriting an existing value until the user edits it.
    /// Letters remain available in names, notes and account references.
    var westernDigits: Binding<String> {
        Binding<String>(
            get: { NumericInput.latinDigits(self.wrappedValue) },
            set: { self.wrappedValue = NumericInput.latinDigits($0) }
        )
    }
}
