import SwiftUI
import UIKit

/// Validates before UIKit inserts text, including paste, dictation and hardware keyboards.
/// Keyboard appearance alone cannot prevent nonnumeric content or normalize Arabic digits.
@MainActor
struct NumericTextField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    @Binding var isFocused: Bool
    let identifier: String
    var accessibilityTitle: String? = nil
    var textAlignment: NSTextAlignment = .left
    var nextTitle: String? = nil
    var doneTitle: String = "Done"
    var nextAction: (() -> Void)? = nil
    let normalize: (_ proposed: String, _ current: String) -> String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .done
        field.textContentType = nil
        field.semanticContentAttribute = .forceLeftToRight
        field.textColor = .label
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.field = field
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = title
        field.keyboardType = keyboardType
        field.isEnabled = context.environment.isEnabled
        field.textAlignment = textAlignment
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityTitle ?? title
        field.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: field.traitCollection)
        if let toolbar = field.inputAccessoryView as? UIToolbar {
            toolbar.semanticContentAttribute = context.environment.layoutDirection == .rightToLeft ?
                .forceRightToLeft : .forceLeftToRight
            var items: [UIBarButtonItem] = []
            if let nextTitle, nextAction != nil {
                items.append(UIBarButtonItem(title: nextTitle, style: .plain,
                    target: context.coordinator, action: #selector(Coordinator.next)))
            }
            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            items.append(UIBarButtonItem(title: doneTitle, style: .done,
                target: context.coordinator, action: #selector(Coordinator.done)))
            if toolbar.items?.map(\.title) != items.map(\.title) { toolbar.setItems(items, animated: false) }
        }
        if field.text != text { field.text = text }
        if !field.isEnabled && field.isFirstResponder {
            DispatchQueue.main.async { [weak field] in
                if field?.isEnabled == false { field?.resignFirstResponder() }
            }
        } else if field.isEnabled && isFocused && !field.isFirstResponder {
            // A new Form row may not have a window until this update finishes.
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard coordinator?.parent.isFocused == true, field?.window != nil, field?.isEnabled == true else { return }
                field?.becomeFirstResponder()
            }
        } else if !isFocused && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? max(80, uiView.intrinsicContentSize.width),
               height: max(28, uiView.intrinsicContentSize.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericTextField
        weak var field: UITextField?
        init(_ parent: NumericTextField) { self.parent = parent }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // Changing focus with Next must not clear the newly focused sibling field.
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.isFocused = false
            textField.resignFirstResponder()
            return false
        }

        @objc func next() {
            parent.nextAction?()
            field?.resignFirstResponder()
        }

        @objc func done() {
            parent.isFocused = false
            field?.resignFirstResponder()
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString replacement: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposal = current.replacingCharacters(in: swiftRange, with: replacement)
            guard let accepted = parent.normalize(proposal, current) else { return false }
            textField.text = accepted
            parent.text = accepted
            // Arabic digit conversion preserves UTF-16 length. A normalizer may also add a
            // leading zero before a decimal point, so account for that before restoring the caret.
            let caret = min(accepted.utf16.count, max(0,
                range.location + replacement.utf16.count + accepted.utf16.count - proposal.utf16.count))
            if let position = textField.position(from: textField.beginningOfDocument, offset: caret) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            return false
        }

        @objc func editingChanged(_ field: UITextField) {
            // Covers any system editing route that sends a change without consulting the delegate.
            guard let accepted = parent.normalize(field.text ?? "", parent.text) else {
                field.text = parent.text
                return
            }
            if field.text != accepted { field.text = accepted }
            parent.text = accepted
        }
    }
}
