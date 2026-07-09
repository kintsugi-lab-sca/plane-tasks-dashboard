import AppKit

/// NSMenuItem que ejecuta un closure y se marca con checkmark si procede.
/// Base de los NSMenu on-demand (ver gotcha: Menu de SwiftUI inline congela
/// el view graph en macOS 26).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, checked: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    @objc private func fire() { handler() }
}
