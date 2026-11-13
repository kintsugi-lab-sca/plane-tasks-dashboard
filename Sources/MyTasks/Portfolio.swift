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

    /// Reunión o correo relevante que el orquestador asoció al proyecto.
    struct Event: Codable, Hashable, Sendable {
        /// "meeting" | "email".
        let kind: String
        let date: String
        let title: String
        let summary: String?
        let ref: String?
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
    /// Opcional: las fichas anteriores a `kodo portfolio event` no lo traen.
    let events: [Event]?
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
        /// Entregadas a la espera de revisión (ver `isReview`).
        var inReview = 0
        /// Activas sin empezar (backlog + unstarted).
        var todo = 0
        var overdue = 0
        /// Fecha límite más próxima (hoy incluido) entre las tareas activas.
        var nextDue: String?

        var total: Int { done + inProgress + inReview + todo }
    }

    /// Plane mete «In Review» en el grupo `started`, junto a «In Progress»:
    /// la única forma de separarlos es el nombre del estado.
    static func isReview(_ state: WorkItemState) -> Bool {
        let name = state.name.lowercased()
        return state.group == "started" && (name.contains("review") || name.contains("revisi"))
    }

    /// Contadores de las tareas de la ficha. `memberIDs` restringe a un módulo
    /// (nil = proyecto entero). Las canceladas no cuentan.
    static func stats(
        items: [WorkItem],
        states: [WorkItemState],
        memberIDs: Set<String>?,
        todayISO: String
    ) -> Stats {
        let byID = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        var stats = Stats()
        for item in items {
            if let memberIDs, !memberIDs.contains(item.id) { continue }
            let state = byID[item.state]
            switch state?.group {
            case "completed":
                stats.done += 1
                continue
            case "cancelled", nil:
                continue
            case "started":
                if state.map(isReview) ?? false { stats.inReview += 1 } else { stats.inProgress += 1 }
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

    /// Fila de la agenda de la ficha: un hito de kodo o el vencimiento de una tarea.
    struct AgendaRow: Equatable, Identifiable {
        let date: String
        let label: String
        /// Tarea de Plane a la que corresponde; nil si es un hito de la ficha.
        let itemID: String?
        let overdue: Bool

        var id: String { "\(date)|\(itemID ?? label)" }
    }

    /// Agenda cronológica: hitos futuros de la ficha y tareas activas con fecha
    /// límite (las vencidas también, marcadas). `items` ya viene restringido a
    /// la ficha. A igualdad de fecha, el hito va antes.
    static func agenda(
        entry: PortfolioEntry,
        items: [WorkItem],
        states: [WorkItemState],
        todayISO: String
    ) -> [AgendaRow] {
        let active = Set(states.filter(\.isActive).map(\.id))
        let milestones = entry.dates
            .filter { $0.date >= todayISO }
            .map { AgendaRow(date: $0.date, label: $0.label, itemID: nil, overdue: false) }
        let tasks = items.compactMap { item -> AgendaRow? in
            guard active.contains(item.state), let target = item.targetDate else { return nil }
            return AgendaRow(date: target, label: item.name, itemID: item.id, overdue: target < todayISO)
        }
        return (milestones + tasks).sorted {
            $0.date != $1.date ? $0.date < $1.date : ($0.itemID == nil && $1.itemID != nil)
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
