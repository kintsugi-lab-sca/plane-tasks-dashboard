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
        /// Instante en que se marcó como cumplido; nil = pendiente.
        var doneAt: String? = nil

        var isDone: Bool { doneAt != nil }
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

    /// Slug de fichero para un nombre: minúsculas ASCII, dígitos y guiones
    /// (misma regla que valida kodo), máximo 40. Vacío si no queda nada.
    static func slug(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            let isAlnum = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            return isAlnum ? Character(scalar) : "-"
        }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .prefix(40)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Crea una ficha vacía (solo nombre y enlace a Plane) con la misma forma
    /// que escribe `kodo portfolio set`. El slug de un módulo lleva delante el
    /// proyecto (`liken-dev`), porque hay módulos homónimos; si aun así existe,
    /// añade un sufijo. Devuelve el slug creado.
    @discardableResult
    static func create(
        name: String,
        projectID: String,
        module: String?,
        projectName: String? = nil,
        in directory: URL,
        now: Date = Date()
    ) throws -> String {
        let source = module != nil ? [projectName, name].compactMap { $0 }.joined(separator: " ") : name
        let base = slug(for: source).isEmpty ? "proyecto" : slug(for: source)
        var slug = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.appending(path: "\(slug).json").path) {
            slug = "\(base.prefix(37))-\(suffix)"
            suffix += 1
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let object: [String: Any] = [
            "schema_version": 1,
            "slug": slug,
            "name": name,
            "plane": ["project_id": projectID, "module": module.map { $0 as Any } ?? NSNull()] as [String: Any],
            "archived": false,
            "status": NSNull(),
            "headline": NSNull(),
            "next_step": NSNull(),
            "waiting_on": NSNull(),
            "blockers": [String](),
            "dates": [Any](),
            "steps": [Any](),
            "events": [Any](),
            "updated_at": formatter.string(from: now),
            "updated_by": "mytasks",
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appending(path: "\(slug).json"), options: .atomic)
        return slug
    }

    /// Campos de situación editables a mano desde la app.
    struct Situation: Equatable {
        var headline = ""
        var nextStep = ""
        var waitingOn = ""
        /// Vacío = sin estado.
        var status = ""

        init(headline: String = "", nextStep: String = "", waitingOn: String = "", status: String = "") {
            self.headline = headline
            self.nextStep = nextStep
            self.waitingOn = waitingOn
            self.status = status
        }

        init(_ entry: PortfolioEntry) {
            self.init(
                headline: entry.headline ?? "", nextStep: entry.nextStep ?? "",
                waitingOn: entry.waitingOn ?? "", status: entry.status ?? ""
            )
        }
    }

    /// Estados del semáforo en orden de menú (vocabulario de kodo).
    static let statuses = ["on_track", "at_risk", "blocked", "waiting", "paused", "done"]

    /// Escribe la situación editada a mano. Texto vacío = campo sin valor.
    /// Conserva el resto del fichero y marca la ficha como actualizada ahora
    /// por `mytasks`. Misma limpieza que kodo: una sola línea, sin espacios
    /// sobrantes.
    static func updateSituation(
        _ situation: Situation,
        slug: String,
        in directory: URL,
        now: Date = Date()
    ) throws {
        let url = directory.appending(path: "\(slug).json")
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        func value(_ text: String) -> Any {
            let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return clean.isEmpty ? NSNull() : clean
        }
        object["headline"] = value(situation.headline)
        object["next_step"] = value(situation.nextStep)
        object["waiting_on"] = value(situation.waitingOn)
        object["status"] = statuses.contains(situation.status) ? situation.status : NSNull()
        object["updated_at"] = isoFractional.string(from: now)
        object["updated_by"] = "mytasks"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Marca (o desmarca) como cumplido el hito de esa fecha y etiqueta. Mismo
    /// campo `done_at` que `kodo portfolio set --done-date`. Cuenta como
    /// actualización de la ficha.
    static func setMilestoneDone(
        _ done: Bool,
        date: String,
        label: String,
        slug: String,
        in directory: URL,
        now: Date = Date()
    ) throws {
        let url = directory.appending(path: "\(slug).json")
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              var dates = object["dates"] as? [[String: Any]],
              let index = dates.firstIndex(where: { $0["date"] as? String == date && $0["label"] as? String == label })
        else { throw CocoaError(.fileReadCorruptFile) }
        let stamp = isoFractional.string(from: now)
        if done {
            if dates[index]["done_at"] as? String == nil { dates[index]["done_at"] = stamp }
        } else {
            dates[index]["done_at"] = nil
        }
        object["dates"] = dates
        object["updated_at"] = stamp
        object["updated_by"] = "mytasks"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Fecha (`yyyy-MM-dd`) del último barrido completo de reuniones y correo
    /// que dejó el orquestador en `.last-sweep`; nil si nunca ha corrido.
    static func lastSweep(in directory: URL) -> String? {
        guard let raw = try? String(contentsOf: directory.appending(path: ".last-sweep"), encoding: .utf8) else {
            return nil
        }
        let day = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return dayFormatter.date(from: day) == nil ? nil : day
    }

    /// Días naturales entre dos días ISO; nil si alguno no es una fecha.
    static func daysBetween(_ fromISO: String, _ toISO: String) -> Int? {
        guard let from = dayFormatter.date(from: fromISO), let to = dayFormatter.date(from: toISO) else { return nil }
        return dayFormatter.calendar.dateComponents([.day], from: from, to: to).day
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
        /// Tareas por estado del grupo `started` (id de estado → recuento). Plane
        /// mete ahí tanto «In Progress» como «In Review»: se cuentan por estado
        /// real, sin adivinar por el nombre cuál es cuál.
        var started: [String: Int] = [:]
        /// Activas sin empezar (backlog + unstarted).
        var todo = 0
        var overdue = 0
        /// Fecha límite más próxima (hoy incluido) entre las tareas activas.
        var nextDue: String?
        /// Completadas en los últimos `deliveredDays` días.
        var deliveredRecently = 0
        /// Completadas DESPUÉS de la última actualización de la ficha: entregas
        /// que la narrativa todavía no recoge (ver `unreported`).
        var unreported = 0

        var total: Int { done + started.values.reduce(0, +) + todo }
    }

    /// Ventana de «entregado recientemente».
    static let deliveredDays = 7

    /// Día ISO (`yyyy-MM-dd`) de hace `days` días respecto a `todayISO`.
    static func dayISO(_ todayISO: String, minusDays days: Int) -> String {
        guard let today = dayFormatter.date(from: todayISO),
              let date = dayFormatter.calendar.date(byAdding: .day, value: -days, to: today)
        else { return todayISO }
        return dayFormatter.string(from: date)
    }

    /// Día de hoy (`yyyy-MM-dd`) en el calendario local.
    static func todayISO(now: Date = Date()) -> String {
        dayFormatter.string(from: now)
    }

    // Compartido por el mismo motivo que los formateadores ISO de abajo.
    private nonisolated(unsafe) static let dayFormatter = GanttLayout.dayFormatter(calendar: .current)

    /// Tareas completadas desde `sinceISO` (día incluido), la más reciente
    /// primero. `items` ya viene restringido a la ficha. La comparación usa el
    /// día UTC de `completed_at`: basta para una ventana de una semana.
    static func delivered(items: [WorkItem], states: [WorkItemState], sinceISO: String) -> [WorkItem] {
        let completed = Set(states.filter { $0.group == "completed" }.map(\.id))
        return items
            .filter { item in
                guard completed.contains(item.state), let at = item.completedAt else { return false }
                return String(at.prefix(10)) >= sinceISO
            }
            .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
    }

    /// Tareas completadas en Plane después de `updated_at` de la ficha. Es la
    /// red de seguridad contra una ficha que nadie actualizó: no depende de que
    /// el orquestador se acuerde, y usa la pertenencia real al módulo (`items`
    /// ya viene restringido a la ficha).
    static func unreported(entry: PortfolioEntry, items: [WorkItem], states: [WorkItemState]) -> Int {
        guard let updated = parseISO(entry.updatedAt) else { return 0 }
        let completed = Set(states.filter { $0.group == "completed" }.map(\.id))
        // Descarte barato antes de parsear: el día escrito en `completed_at`
        // (en el huso que sea) dista como mucho uno del día UTC, así que todo
        // lo anterior a la víspera de la ficha no puede ser posterior a ella.
        let cutoffDay = String(isoPlain.string(from: updated.addingTimeInterval(-86400)).prefix(10))
        return items.count { item in
            guard completed.contains(item.state), let raw = item.completedAt, raw.prefix(10) >= cutoffDay,
                  let at = parseISO(raw)
            else { return false }
            return at > updated
        }
    }

    /// Cuánta atención pide una ficha; ordena el portafolio y alimenta el badge.
    enum Attention: Int, Comparable {
        case none, stale, overdue, blocked

        static func < (a: Attention, b: Attention) -> Bool { a.rawValue < b.rawValue }
    }

    /// Bloqueada (bloqueos o estado `blocked`) > con tareas vencidas o en
    /// riesgo > narrativa ausente o antigua. Una ficha pausada o terminada no
    /// pide atención.
    static func attention(entry: PortfolioEntry, stats: Stats?, now: Date) -> Attention {
        if entry.archived || entry.status == "paused" || entry.status == "done" { return .none }
        if !entry.blockers.isEmpty || entry.status == "blocked" { return .blocked }
        let today = todayISO(now: now)
        let missedMilestone = entry.dates.contains { !$0.isDone && $0.date < today }
        if (stats?.overdue ?? 0) > 0 || missedMilestone || entry.status == "at_risk" { return .overdue }
        let age = ageInDays(updatedAt: entry.updatedAt, now: now) ?? 0
        if entry.headline == nil || age > staleDays || (stats?.unreported ?? 0) > 0 { return .stale }
        return .none
    }

    /// Nombre del estado «en revisión» tal como lo tiene configurado kodo
    /// (`providers.plane.states.review` de `~/.kodo/config.json`). Es un dato
    /// declarado, no una adivinanza por el nombre: Plane no distingue revisión
    /// de en curso (ambos son `started`).
    static func reviewStateName(kodoConfig url: URL) -> String? {
        kodoStateName("review", kodoConfig: url)
    }

    /// Nombre de un estado según la config de kodo
    /// (`providers.plane.states.<key>`: `trigger`, `review`, `done`).
    static func kodoStateName(_ key: String, kodoConfig url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any],
              let plane = providers["plane"] as? [String: Any],
              let states = plane["states"] as? [String: Any],
              let name = states[key] as? String, !name.isEmpty
        else { return nil }
        return name
    }

    /// Estado al que pasa una tarea al darla por hecha: del grupo `completed`,
    /// el que kodo declara como `done` (sin distinguir mayúsculas) y, si no hay
    /// coincidencia, el primero del proyecto.
    static func doneState(in states: [WorkItemState], doneName: String?) -> WorkItemState? {
        let completed = states.filter { $0.group == "completed" }.sorted { $0.sequence < $1.sequence }
        if let doneName,
           let match = completed.first(where: { $0.name.compare(doneName, options: .caseInsensitive) == .orderedSame }) {
            return match
        }
        return completed.first
    }

    /// true si `state` es el estado de revisión declarado (sin distinguir
    /// mayúsculas: «In review» en un proyecto, «In Review» en otro). Una tarea
    /// en revisión ya está entregada: su fecha límite pasada no es un retraso.
    static func isReview(_ state: WorkItemState?, reviewState: String?) -> Bool {
        guard let state, let reviewState, state.group == "started" else { return false }
        return state.name.compare(reviewState, options: .caseInsensitive) == .orderedSame
    }

    /// Contadores de las tareas de la ficha. `memberIDs` restringe a un módulo
    /// (nil = proyecto entero). Las canceladas no cuentan.
    static func stats(
        items: [WorkItem],
        states: [WorkItemState],
        memberIDs: Set<String>?,
        todayISO: String,
        reviewState: String? = nil
    ) -> Stats {
        let groups = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0.group) })
        let reviewIDs = Set(states.filter { isReview($0, reviewState: reviewState) }.map(\.id))
        var stats = Stats()
        let since = dayISO(todayISO, minusDays: deliveredDays)
        for item in items {
            if let memberIDs, !memberIDs.contains(item.id) { continue }
            switch groups[item.state] {
            case "completed":
                stats.done += 1
                if let at = item.completedAt, String(at.prefix(10)) >= since { stats.deliveredRecently += 1 }
                continue
            case "cancelled", nil:
                continue
            case "started":
                stats.started[item.state, default: 0] += 1
            default:
                stats.todo += 1
            }
            guard let target = item.targetDate else { continue }
            if target < todayISO {
                // En revisión = entregada: no cuenta como vencida.
                if !reviewIDs.contains(item.state) { stats.overdue += 1 }
            } else if stats.nextDue.map({ target < $0 }) ?? true {
                stats.nextDue = target
            }
        }
        return stats
    }

    /// Fila de la agenda conjunta: una fecha de una ficha concreta.
    struct WeekRow: Equatable, Identifiable {
        let slug: String
        let entryName: String
        let row: AgendaRow

        var id: String { "\(slug)|\(row.id)" }
    }

    /// Día de la agenda conjunta; `date == nil` agrupa lo ya vencido.
    struct WeekDay: Equatable, Identifiable {
        let date: String?
        let rows: [WeekRow]

        var id: String { date ?? "vencidas" }
    }

    /// Días vista de la agenda conjunta (hoy incluido aparte).
    static let agendaDays = 14

    /// Agenda que cruza todas las fichas: primero lo vencido y después un
    /// grupo por día hasta `days` días vista. Dentro de cada día, los hitos
    /// antes que las tareas y, a igualdad, por ficha.
    static func weekAgenda(
        _ perEntry: [(entry: PortfolioEntry, rows: [AgendaRow])],
        todayISO: String,
        days: Int = agendaDays
    ) -> [WeekDay] {
        let limit = dayISO(todayISO, minusDays: -days)
        let all = perEntry.flatMap { pair in
            pair.rows.map { WeekRow(slug: pair.entry.slug, entryName: pair.entry.name, row: $0) }
        }
        let overdue = all.filter(\.row.overdue).sorted { $0.row.date < $1.row.date }
        let upcoming = all.filter { !$0.row.overdue && $0.row.date >= todayISO && $0.row.date <= limit }
        let byDay = Dictionary(grouping: upcoming, by: \.row.date)
        var result: [WeekDay] = overdue.isEmpty ? [] : [WeekDay(date: nil, rows: overdue)]
        for day in byDay.keys.sorted() {
            let rows = (byDay[day] ?? []).sorted { a, b in
                let aMilestone = a.row.itemID == nil, bMilestone = b.row.itemID == nil
                if aMilestone != bMilestone { return aMilestone }
                return a.entryName.localizedCaseInsensitiveCompare(b.entryName) == .orderedAscending
            }
            result.append(WeekDay(date: day, rows: rows))
        }
        return result
    }

    /// Próxima fecha relevante: el hito de la ficha o el vencimiento de tarea
    /// más cercano, lo que llegue antes (a igualdad, el hito).
    static func upcoming(entry: PortfolioEntry, stats: Stats?, todayISO: String) -> PortfolioEntry.Milestone? {
        let milestone = entry.dates.filter { !$0.isDone && $0.date >= todayISO }.min { $0.date < $1.date }
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
        /// Hito marcado como cumplido.
        var done = false
        /// Estado de Plane de la tarea (nombre y color "#RRGGBB"); nil en hitos.
        var stateName: String? = nil
        var stateColor: String? = nil

        var id: String { "\(date)|\(itemID ?? label)" }
    }

    /// Días que un hito cumplido sigue viéndose en la ficha tras su fecha.
    static let doneMilestoneDays = 7

    /// Agenda cronológica: hitos de la ficha y tareas activas con fecha límite.
    /// Un hito pendiente cuya fecha pasó cuenta como vencido (hasta que se
    /// marque cumplido); uno cumplido se sigue viendo una semana, como
    /// historia. `items` ya viene restringido a la ficha. A igualdad de fecha,
    /// el hito va antes.
    static func agenda(
        entry: PortfolioEntry,
        items: [WorkItem],
        states: [WorkItemState],
        todayISO: String,
        reviewState: String? = nil
    ) -> [AgendaRow] {
        let active = Dictionary(uniqueKeysWithValues: states.filter(\.isActive).map { ($0.id, $0) })
        let keepDoneSince = dayISO(todayISO, minusDays: doneMilestoneDays)
        let milestones = entry.dates
            .filter { !$0.isDone || $0.date >= keepDoneSince }
            .map {
                AgendaRow(
                    date: $0.date, label: $0.label, itemID: nil,
                    overdue: !$0.isDone && $0.date < todayISO, done: $0.isDone
                )
            }
        let tasks = items.compactMap { item -> AgendaRow? in
            guard let state = active[item.state], let target = item.targetDate else { return nil }
            // Rojo solo para lo que tiene fecha y no se ha cumplido: una tarea
            // en revisión ya está entregada.
            let overdue = target < todayISO && !isReview(state, reviewState: reviewState)
            return AgendaRow(
                date: target, label: item.name, itemID: item.id, overdue: overdue,
                stateName: state.name, stateColor: state.color
            )
        }
        return (milestones + tasks).sorted {
            $0.date != $1.date ? $0.date < $1.date : ($0.itemID == nil && $1.itemID != nil)
        }
    }

    /// Días transcurridos desde `updated_at` (ISO 8601, con o sin milisegundos).
    static func ageInDays(updatedAt: String, now: Date) -> Int? {
        guard let date = parseISO(updatedAt) else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 86400))
    }

    /// Instante ISO 8601, con o sin fracción de segundo (kodo escribe
    /// milisegundos; Plane, microsegundos).
    static func parseISO(_ iso: String) -> Date? {
        isoFractional.date(from: iso) ?? isoPlain.date(from: iso)
    }

    // Compartidos: crear un ISO8601DateFormatter por llamada costaba ~2 s por
    // repintado del portafolio (uno por tarea completada y ficha). La clase es
    // segura entre hilos y no se muta tras configurarla.
    private nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()
    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
