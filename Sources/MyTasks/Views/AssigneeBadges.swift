import SwiftUI

/// Iniciales de los asignados en círculos de color (determinista por id de
/// usuario, estable entre lanzamientos). Con `showEmpty`, una tarea sin
/// asignar pinta un círculo punteado: así se detectan de un vistazo las
/// tareas que crean las integraciones (kodo) sin asignee.
struct AssigneeBadges: View {
    @Environment(AppState.self) private var app
    let item: WorkItem
    /// Diámetro de cada círculo (el caller ya aplica fontScale).
    var size: CGFloat = 15
    var showEmpty = false

    private static let maxShown = 3

    var body: some View {
        let users = app.assignees(for: item)
        if users.isEmpty {
            if showEmpty {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: size, height: size)
                    .help("Sin asignar")
            }
        } else {
            HStack(spacing: -size * 0.3) {
                ForEach(users.prefix(Self.maxShown)) { user in
                    badge(user)
                }
                if users.count > Self.maxShown {
                    Text("+\(users.count - Self.maxShown)")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(app.theme.secondaryStyle)
                        .padding(.leading, size * 0.35)
                }
            }
            .help(users.map { $0.displayName ?? "?" }.joined(separator: ", "))
        }
    }

    private func badge(_ user: UserLite) -> some View {
        Text(Self.initials(user.displayName))
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.color(for: user.id), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
    }

    /// "Alex Núñez" → "AN"; una sola palabra → sus dos primeras letras.
    static func initials(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Tono derivado del id con un hash propio: `hashValue` cambia de semilla
    /// en cada lanzamiento y los colores no serían estables.
    static func color(for id: String) -> Color {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.5, brightness: 0.62)
    }
}
