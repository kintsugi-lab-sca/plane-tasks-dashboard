import AppKit
import Carbon.HIToolbox

/// Atajo de teclado global para alternar el panel. Usa Carbon
/// RegisterEventHotKey: funciona sin permisos de accesibilidad y puede
/// consumir el evento (a diferencia de NSEvent.addGlobalMonitor).
@MainActor
final class HotKey {
    static let shared = HotKey()

    /// Combos ofrecidos en Ajustes. El id se persiste en AppSettings.
    static let options: [(id: String, label: String, keyCode: UInt32, modifiers: UInt32)] = [
        ("none", "Desactivado", 0, 0),
        ("opt-space", "⌥ Espacio", UInt32(kVK_Space), UInt32(optionKey)),
        ("cmd-opt-space", "⌘⌥ Espacio", UInt32(kVK_Space), UInt32(cmdKey | optionKey)),
        ("ctrl-opt-t", "⌃⌥ T", UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey)),
        ("cmd-shift-k", "⌘⇧ K", UInt32(kVK_ANSI_K), UInt32(cmdKey | shiftKey)),
    ]

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    /// (Re)registra el combo con ese id; "none" o desconocido lo desactiva.
    func apply(_ id: String) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        guard let option = Self.options.first(where: { $0.id == id }), option.id != "none" else { return }
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D_54_4B_31), id: 1) // 'MTK1'
        let status = RegisterEventHotKey(option.keyCode, option.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        Self.trace("register \(option.id) status=\(status)")
    }

    /// Traza a fichero: NSLog sale redactado en el log unificado.
    static func trace(_ message: String) {
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8), let handle = FileHandle(forWritingAtPath: "/tmp/mytasks-hotkey.txt") {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? line.write(toFile: "/tmp/mytasks-hotkey.txt", atomically: true, encoding: .utf8)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppWindows.shared.togglePanel() }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = true
    }
}
