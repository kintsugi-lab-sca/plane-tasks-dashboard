import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var token: String = Keychain.readToken() ?? ""
    @State private var notifDenied = false
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Conexión") {
                TextField("URL base", text: $app.settings.baseURL, prompt: Text("https://plane.miempresa.com"))
                TextField("Workspace slug", text: $app.settings.workspaceSlug, prompt: Text("mi-workspace"))
                SecureField("API token", text: $token, prompt: Text("plane_api_…"))
                HStack {
                    Button("Guardar y probar conexión") {
                        Keychain.saveToken(token)
                        app.tokenSaved()
                    }
                    if let error = app.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else if app.client != nil, !app.projects.isEmpty {
                        Label("Conectado", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Apariencia") {
                Picker("Tema", selection: $app.settings.themeID) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Picker("Tamaño de letra", selection: $app.settings.fontScale) {
                    Text("Pequeña").tag(0.9)
                    Text("Normal").tag(1.0)
                    Text("Grande").tag(1.15)
                    Text("Muy grande").tag(1.3)
                }
                .pickerStyle(.segmented)
                ColorPicker("Acento", selection: overrideBinding(\.accentHex, current: app.theme.accent ?? .accentColor))
                ColorPicker("Fondo", selection: overrideBinding(\.backgroundHex, current: app.theme.background ?? .clear))
                ColorPicker("Columnas", selection: overrideBinding(\.surfaceHex, current: app.theme.surfaceColor))
                ColorPicker("Tarjetas", selection: overrideBinding(\.cardHex, current: app.theme.card ?? .clear))
                if hasOverrides {
                    Button("Restablecer colores del tema") {
                        app.settings.accentHex = nil
                        app.settings.backgroundHex = nil
                        app.settings.surfaceHex = nil
                        app.settings.cardHex = nil
                    }
                }
            }

            Section("Visualización") {
                Toggle("Mostrar solo tareas asignadas a mí", isOn: $app.settings.onlyMine)
                Picker("Contador del icono", selection: $app.settings.badgeMode) {
                    Text("Todas las tareas").tag("all")
                    Text("Solo urgentes").tag("urgent")
                    Text("Solo vencidas").tag("overdue")
                    Text("Oculto").tag("hidden")
                }
                Picker("Atajo global del panel", selection: $app.settings.hotKeyID) {
                    ForEach(HotKey.options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                Stepper(
                    "Actualizar cada \(app.settings.refreshMinutes) min",
                    value: $app.settings.refreshMinutes,
                    in: 1...60
                )
                Toggle("Abrir al iniciar sesión", isOn: loginItemBinding)
                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Section("Notificaciones") {
                if Notifier.isAvailable {
                    Toggle("Notificar cambios en las tareas", isOn: notifyBinding)
                    Toggle("Avisar de vencimientos (hoy y mañana)", isOn: dueSoonBinding)
                    if notifDenied {
                        Text("Permiso denegado (\(Notifier.shared.lastError ?? "sin detalle")). Actívalo en Ajustes del Sistema → Notificaciones → MyTasks.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if app.settings.notifyChanges {
                        Button("Probar notificación") {
                            Notifier.shared.notify(
                                title: "MyTasks",
                                body: "Las notificaciones funcionan.",
                                url: nil
                            )
                        }
                    }
                } else {
                    Text("Disponible solo en la app instalada como bundle (make install).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Proyectos visibles") {
                if app.projects.isEmpty {
                    Button("Cargar proyectos") {
                        Task { await app.refresh() }
                    }
                } else {
                    ForEach(app.projects) { project in
                        Toggle("\(project.identifier) — \(project.name)", isOn: visibleBinding(for: project))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
    }

    private var hasOverrides: Bool {
        app.settings.accentHex != nil || app.settings.backgroundHex != nil
            || app.settings.surfaceHex != nil || app.settings.cardHex != nil
    }

    /// Registra/da de baja la app como login item (SMAppService, macOS 13+).
    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemEnabled },
            set: { on in
                do {
                    if on {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginItemEnabled = on
                    loginItemError = nil
                } catch {
                    loginItemEnabled = SMAppService.mainApp.status == .enabled
                    loginItemError = error.localizedDescription
                }
            }
        )
    }

    /// Al activar el toggle se pide el permiso del sistema (diálogo la primera vez).
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notifyChanges },
            set: { on in
                app.settings.notifyChanges = on
                guard on else { return }
                Task { notifDenied = await !Notifier.shared.requestAuthorization() }
            }
        )
    }

    private var dueSoonBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notifyDueSoon },
            set: { on in
                app.settings.notifyDueSoon = on
                guard on else { return }
                Task { notifDenied = await !Notifier.shared.requestAuthorization() }
            }
        )
    }

    /// Binding para un ColorPicker que escribe el override como hex en settings.
    private func overrideBinding(_ keyPath: WritableKeyPath<AppSettings, String?>, current: Color) -> Binding<Color> {
        Binding(
            get: { Color(hex: app.settings[keyPath: keyPath]) ?? current },
            set: { app.settings[keyPath: keyPath] = $0.hexString }
        )
    }

    private func visibleBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { app.settings.visibleProjectIDs.contains(project.id) },
            set: { on in
                if on {
                    app.settings.visibleProjectIDs.insert(project.id)
                } else {
                    app.settings.visibleProjectIDs.remove(project.id)
                }
                Task { await app.refresh() }
            }
        )
    }
}
