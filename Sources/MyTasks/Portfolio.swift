import Foundation

/// Ficha de un proyecto del portafolio. La escribe kodo (`kodo portfolio set|step`)
/// en `~/.kodo/portfolio/<slug>.json`; MyTasks solo la lee (y la archiva).
/// Guarda la narrativa que no se puede derivar; los contadores salen de Plane.
struct PortfolioEntry: Codable, Identifiable, Hashable, Sendable {
    struct PlaneRef: Codable, Hashable, Sendable {
        let projectId: String
        /// Nombre del módulo de Plane si el proyecto es un módulo; nil = proyecto entero.
        let module: String?
    }

    struct Milestone: Codable, Hashable, Sendable {
        let date: String
        let label: String
    }

    struct Step: Codable, Hashable, Sendable {
        let at: String
        let text: String
        let source: String?
    }

    let slug: String
    let name: String
    let plane: PlaneRef
    let archived: Bool
    let status: String?
    let headline: String?
    let nextStep: String?
    let waitingOn: String?
    let blockers: [String]
    let dates: [Milestone]
    let steps: [Step]
    let updatedAt: String
    let updatedBy: String?

    var id: String { slug }
}

/// Lectura del portafolio y cálculos derivados (puro salvo el acceso a disco,
/// que recibe el directorio por parámetro para poder testearse).
enum Portfolio {
    /// Días sin actualizar a partir de los cuales la narrativa se marca como antigua.
    static let staleDays = 7

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kodo/portfolio")
    }

    /// Fichas legibles del directorio, por nombre. Una ficha corrupta se omite.
    static func load(from directory: URL) -> [PortfolioEntry] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PortfolioEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Cambia solo `archived`, conservando el resto del fichero tal cual
    /// (incluidos campos que esta versión no conozca). Escritura atómica.
    static func setArchived(_ archived: Bool, slug: String, in directory: URL) throws {
        let url = directory.appending(path: "\(slug).json")
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        object["archived"] = archived
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Datos derivados de Plane

    struct Stats: Equatable {
        var done = 0
        var inProgress = 0
        /// Activas sin empezar (backlog + unstarted).
        var todo = 0
        var overdue = 0
        /// Fecha límite más próxima (hoy incluido) entre las tareas activas.
        var nextDue: String?

        var total: Int { done + inProgress + todo }
    }

    /// Contadores de las tareas de la ficha. `memberIDs` restringe a un módulo
    /// (nil = proyecto entero). Las canceladas no cuentan.
    static func stats(
        items: [WorkItem],
        states: [WorkItemState],
        memberIDs: Set<String>?,
        todayISO: String
    ) -> Stats {
        let groups = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0.group) })
        var stats = Stats()
        for item in items {
            if let memberIDs, !memberIDs.contains(item.id) { continue }
            switch groups[item.state] {
            case "completed":
                stats.done += 1
                continue
            case "cancelled", nil:
                continue
            case "started":
                stats.inProgress += 1
            default:
                stats.todo += 1
            }
            guard let target = item.targetDate else { continue }
            if target < todayISO {
                stats.overdue += 1
            } else if stats.nextDue.map({ target < $0 }) ?? true {
                stats.nextDue = target
            }
        }
        return stats
    }

    /// Próxima fecha relevante: el hito de la ficha o el vencimiento de tarea
    /// más cercano, lo que llegue antes (a igualdad, el hito).
    static func upcoming(entry: PortfolioEntry, stats: Stats?, todayISO: String) -> PortfolioEntry.Milestone? {
        let milestone = entry.dates.filter { $0.date >= todayISO }.min { $0.date < $1.date }
        let due = stats?.nextDue.map { PortfolioEntry.Milestone(date: $0, label: "Vence tarea") }
        switch (milestone, due) {
        case let (m?, d?): return d.date < m.date ? d : m
        default: return milestone ?? due
        }
    }

    /// Días transcurridos desde `updated_at` (ISO 8601, con o sin milisegundos).
    static func ageInDays(updatedAt: String, now: Date) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: updatedAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: updatedAt)
        }
        guard let date else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 86400))
    }

    /// Etiqueta visible del semáforo (vocabulario de kodo).
    static func statusLabel(_ status: String?) -> String? {
        switch status {
        case "on_track": "En marcha"
        case "at_risk": "En riesgo"
        case "blocked": "Bloqueado"
        case "waiting": "En espera"
        case "paused": "Pausado"
        case "done": "Terminado"
        default: nil
        }
    }
}
