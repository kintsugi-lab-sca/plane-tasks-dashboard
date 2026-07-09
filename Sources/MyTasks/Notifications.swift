import AppKit
import UserNotifications

/// Notificaciones nativas del sistema. UNUserNotificationCenter exige un bundle
/// real: en el binario suelto de `swift build` current() lanza una excepción,
/// de ahí el guard de `isAvailable` antes de cualquier llamada.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private(set) var authorized = false
    /// Error de la última petición de permiso, para mostrarlo en Ajustes.
    private(set) var lastError: String?

    /// Engancha el delegate (clic en la notificación) y refresca `authorized`.
    func start() {
        NSLog("MyTasks notif start(): bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "nil")")
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        Task {
            NSLog("MyTasks notif consultando settings…")
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorized = settings.authorizationStatus == .authorized
            NSLog("MyTasks notif status al arrancar: \(settings.authorizationStatus.rawValue)")
        }
    }

    /// Pide permiso al sistema (la primera vez muestra el diálogo).
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            lastError = authorized ? nil : "Permiso no concedido"
        } catch {
            authorized = false
            lastError = error.localizedDescription
            NSLog("MyTasks notif requestAuthorization error: \(error)")
        }
        return authorized
    }

    func notify(title: String, body: String, url: URL?) {
        guard Self.isAvailable, authorized else {
            NSLog("MyTasks notify descartada: available=\(Self.isAvailable) authorized=\(authorized)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("MyTasks notify add error: \(error)") }
        }
    }

    /// Muestra el banner aunque la app esté "activa" (agente de barra de menú).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Clic en la notificación: abre la tarea en Plane; sin URL, abre el tablero.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        completionHandler()
        Task { @MainActor in
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else {
                AppWindows.shared.showBoard()
            }
        }
    }
}
