import RemoteKit
import SwiftUI
import UIKit

/// A thin text strip above the system keyboard whose contents are mirrored to the Mac.
///
/// It's a real `UITextField` (not a bare `UIKeyInput` view) so the keyboard's own mic /
/// dictation, autocorrect and predictive text all work. Every edit is diffed against the previous
/// text: the removed tail becomes backspaces and the inserted tail becomes `text`, so an
/// autocorrect or dictation revision rewrites the Mac's text correctly instead of appending.
struct KeyboardInputView: UIViewRepresentable {
    let client: RemoteClient
    @Binding var isActive: Bool
    let onActivity: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KeyboardField {
        let coordinator = context.coordinator
        let binding = $isActive
        coordinator.send = { [client] in client.send($0) }
        coordinator.onActivity = onActivity
        coordinator.onDone = { binding.wrappedValue = false }

        let field = KeyboardField()
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.onEmptyBackspace = { [weak coordinator] in coordinator?.emit(.backspace) }
        field.inputAccessoryView = coordinator.makeAccessoryBar()
        coordinator.field = field

        // Becoming first responder must wait until the view is in a window.
        Task { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: KeyboardField, context: Context) {
        context.coordinator.onActivity = onActivity
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var send: (Message) -> Void = { _ in }
        var onActivity: () -> Void = {}
        var onDone: () -> Void = {}
        weak var field: KeyboardField?

        private var accessory: AccessoryBar?
        private var previous = ""
        private var commandLatched = false {
            didSet { accessory?.setCommandLatched(commandLatched) }
        }

        /// Only the letters the wire protocol can carry with ⌘.
        private static let shortcutLetters: [Character: KeyCode] = [
            "f": .f, "m": .m, "c": .c, "k": .k, "j": .j, "l": .l, "t": .t, "w": .w,
        ]

        func makeAccessoryBar() -> AccessoryBar {
            let bar = AccessoryBar(
                onKey: { [weak self] in self?.emit($0) },
                onCommand: { [weak self] in
                    guard let self else { return }
                    commandLatched.toggle()
                },
                onDone: { [weak self] in self?.field?.resignFirstResponder() }
            )
            accessory = bar
            return bar
        }

        /// A special key, with ⌘ applied once if it is latched.
        func emit(_ key: KeyCode) {
            onActivity()
            let modifiers: KeyModifiers = commandLatched ? .command : []
            commandLatched = false
            send(.key(key, modifiers: modifiers))
        }

        @objc func editingChanged(_ field: UITextField) {
            onActivity()
            let new = field.text ?? ""
            let old = previous
            guard new != old else { return }

            // ⌘ + a letter is a shortcut, not text: send the key and keep the buffer unchanged.
            if commandLatched, new.count == old.count + 1, new.hasPrefix(old), let typed = new.last {
                field.text = old
                if let key = Self.shortcutLetters[Character(typed.lowercased())] {
                    commandLatched = false
                    send(.key(key, modifiers: .command))
                }
                return
            }

            let oldCharacters = Array(old)
            let newCharacters = Array(new)
            var common = 0
            while common < min(oldCharacters.count, newCharacters.count),
                  oldCharacters[common] == newCharacters[common] {
                common += 1
            }
            for _ in 0..<(oldCharacters.count - common) { send(.key(.backspace)) }
            for message in Message.textMessages(for: String(newCharacters[common...])) { send(message) }
            previous = new
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            onActivity()
            send(.key(.return))
            field.text = ""
            previous = ""
            return false // keep the keyboard up
        }

        /// Keep the caret at the end: edits are mirrored as "append / delete from the end".
        func textFieldDidChangeSelection(_ field: UITextField) {
            guard field.markedTextRange == nil,
                  let selected = field.selectedTextRange,
                  selected.start != field.endOfDocument || selected.end != field.endOfDocument
            else { return }
            field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            field.text = ""
            previous = ""
            commandLatched = false
            onDone()
        }
    }
}

final class KeyboardField: UITextField {
    var onEmptyBackspace: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        textColor = .white
        tintColor = .white
        font = .systemFont(ofSize: 17)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        leftViewMode = .always
        attributedPlaceholder = NSAttributedString(
            string: "Typing on your Mac…",
            attributes: [.foregroundColor: UIColor(white: 1, alpha: 0.35)]
        )
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        keyboardAppearance = .dark
        returnKeyType = .default
        clearButtonMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// With nothing in the buffer, backspace should still delete on the Mac.
    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onEmptyBackspace?()
        } else {
            super.deleteBackward()
        }
    }
}

/// Esc, Tab, arrows, a one-shot ⌘ latch, and Done, shown above the keyboard.
final class AccessoryBar: UIInputView {
    private let commandButton = UIButton(type: .system)

    init(onKey: @escaping (KeyCode) -> Void, onCommand: @escaping () -> Void, onDone: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        autoresizingMask = .flexibleWidth

        func button(_ title: String, action: @escaping () -> Void) -> UIButton {
            let button = title == "⌘" ? commandButton : UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            button.layer.cornerRadius = 8
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return button
        }

        let buttons = [
            button("Esc") { onKey(.escape) },
            button("Tab") { onKey(.tab) },
            button("←") { onKey(.arrowLeft) },
            button("↑") { onKey(.arrowUp) },
            button("↓") { onKey(.arrowDown) },
            button("→") { onKey(.arrowRight) },
            button("⌘") { onCommand() },
            button("Done") { onDone() },
        ]
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setCommandLatched(_ latched: Bool) {
        commandButton.backgroundColor = latched ? UIColor.white.withAlphaComponent(0.3) : .clear
    }
}
