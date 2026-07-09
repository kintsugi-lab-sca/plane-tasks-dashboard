import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWindows.shared.start()
        Notifier.shared.start()
        HotKey.shared.apply(AppState.shared.settings.hotKeyID)
        // Prueba de notificaciones sin pasar por la UI: MYTASKS_NOTIF_TEST=1
        // pide permiso, notifica y vuelca el resultado a /tmp/mytasks-notif-test.txt.
        if ProcessInfo.processInfo.environment["MYTASKS_NOTIF_TEST"] != nil {
            Task {
                let granted = await Notifier.shared.requestAuthorization()
                let report = "granted=\(granted) lastError=\(Notifier.shared.lastError ?? "nil")"
                try? report.write(toFile: "/tmp/mytasks-notif-test.txt", atomically: true, encoding: .utf8)
                Notifier.shared.notify(title: "MyTasks", body: "Prueba de notificación.", url: nil)
            }
        }
    }
}

@main
struct MyTasksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
    }
}
