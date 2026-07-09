import AppKit
import SwiftUI

/// Panel borderless que puede ser key (necesario para cerrarse al perder el foco).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Gestiona el status item, el panel anclado al borde derecho y la ventana del tablero.
/// Sustituye a MenuBarExtra para poder controlar la posición del desplegable.
@MainActor
final class AppWindows: NSObject, NSWindowDelegate {
    static let shared = AppWindows()

    private let app = AppState.shared
    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var boardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var panelClosedAt: Date = .distantPast

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "MyTasks")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item
        observeBadge()
    }

    /// Reobserva badgeCount en cada cambio (@Observable + withObservationTracking).
    private func observeBadge() {
        withObservationTracking {
            let count = app.badgeCount
            statusItem?.button?.title = count > 0 ? " \(count)" : ""
        } onChange: {
            Task { @MainActor in AppWindows.shared.observeBadge() }
        }
    }

    // MARK: - Panel

    /// Alterna el panel; lo invocan el clic en el status item y el atajo global.
    @objc func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else if Date().timeIntervalSince(panelClosedAt) > 0.3 {
            // El clic en el icono puede haber cerrado ya el panel al robarle el
            // foco; sin este umbral el mismo clic lo reabriría al instante.
            showPanel()
        }
    }

    private func showPanel() {
        if panel == nil {
            let root = MenuContentView()
                .environment(app)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.quaternary))
            let hosting = NSHostingView(rootView: root)
            let newPanel = KeyablePanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .statusBar
            newPanel.collectionBehavior = [.transient, .ignoresCycle]
            newPanel.isReleasedWhenClosed = false
            newPanel.delegate = self
            newPanel.contentView = hosting
            hosting.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(panelContentChanged),
                name: NSView.frameDidChangeNotification, object: hosting
            )
            panel = newPanel
        }
        repositionPanel()
        panel?.makeKeyAndOrderFront(nil)
        Task { await app.refresh() }
    }

    func closePanel() {
        panel?.orderOut(nil)
    }

    /// Ancla el panel al borde derecho de la pantalla del status item, bajo la barra.
    private func repositionPanel() {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0,
              let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        else { return }
        let vf = screen.visibleFrame
        let x = vf.maxX - size.width - 8
        let y = vf.maxY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    @objc private func panelContentChanged() {
        guard let panel, panel.isVisible else { return }
        repositionPanel()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == panel else { return }
        // Diferido un tick: si el foco pasó a una ventana hija (el popover de
        // detalle de una card), cerrar el panel también mataría el popover.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            if let key = NSApp.keyWindow, key.parent == panel || key == panel { return }
            self.panelClosedAt = Date()
            self.closePanel()
        }
    }

    // MARK: - Ventana de tablero y Ajustes

    func showBoard() {
        closePanel()
        if boardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // Sin esto, en una app LSUIElement el botón verde degrada a zoom
            // en lugar de entrar en pantalla completa.
            window.collectionBehavior = [.fullScreenPrimary]
            window.center()
            window.setFrameAutosaveName("boardWindow")
            window.contentView = NSHostingView(
                rootView: MenuContentView(isWindow: true).environment(app)
            )
            boardWindow = window
        }
        boardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        closePanel()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Ajustes de MyTasks"
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("settingsWindow")
            window.contentView = NSHostingView(rootView: SettingsView().environment(app))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
