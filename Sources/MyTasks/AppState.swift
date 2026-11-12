import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.refreshMinutes != oldValue.refreshMinutes {
                startAutoRefresh()
            }
            if settings.hotKeyID != oldValue.hotKeyID {
                HotKey.shared.apply(settings.hotKeyID)
            }
        }
    }

    var projects: [Project] = []
    var itemsByProject: [String: [WorkItem]] = [:]
    var statesByProject: [String: [WorkItemState]] = [:]
    var modulesByProject: [String: [Module]] = [:]
    var moduleItemIDs: [String: Set<String>] = [:]
    var cyclesByProject: [String: [Cycle]] = [:]
    var cycleItemIDs: [String: Set<String>] = [:]
    var labelsByProject: [String: [WorkItemLabel]] = [:]
    var membersByProject: [String: [UserLite]] = [:]
    var myUserID: String?
    /// Fichas del portafolio (~/.kodo/portfolio), recargadas al cambiar el directorio.
    var portfolio: [PortfolioEntry] = []
    /// Filtro de búsqueda del panel (client-side, no persistido).
    var searchText = ""
    /// Filtro por prioridad exacta (valor API: "urgent"…"none"); nil = todas.
    /// Client-side y no persistido, como la búsqueda.
    var priorityFilter: String?
    var isRefreshing = false
    var lastError: String?
    var hasToken: Bool

    var selectedProjectID: String? {
        didSet {
            guard selectedProjectID != oldValue else { return }
            UserDefaults.standard.set(selectedProjectID, forKey: "selectedProjectID")
            selectedModuleID = nil
            selectedCycleID = nil
            Task {
                await loadModules()
                await loadModuleMemberships()
                await loadCycles()
                await loadCycleMemberships()
            }
        }
    }

    var selectedModuleID: String? {
        didSet {
            guard selectedModuleID != oldValue else { return }
            Task { await loadModuleItems() }
        }
    }

    var selectedCycleID: String? {
        didSet {
            guard selectedCycleID != oldValue else { return }
            Task { await loadCycleItems() }
        }
    }

    private var refreshLoop: Task<Void, Never>?
    private var portfolioWatcher: DispatchSourceFileSystemObject?

    /// Token cacheado en memoria: el Keychain se lee UNA vez al arrancar (y al
    /// guardar un token nuevo). Leerlo en cada acceso puede disparar el diálogo
    /// de permiso de macOS repetidamente y bloquear la app.
    private var cachedToken: String?

    init() {
        settings = AppSettings.load()
        let token = Keychain.readToken()
        cachedToken = token
        hasToken = token?.isEmpty == false
        selectedProjectID = UserDefaults.standard.string(forKey: "selectedProjectID")
        watchPortfolio()
        startAutoRefresh()
    }

    var client: PlaneClient? {
        guard let token = cachedToken, !token.isEmpty,
              !settings.workspaceSlug.isEmpty, !settings.normalizedBaseURL.isEmpty
        else { return nil }
        return PlaneClient(baseURL: settings.normalizedBaseURL, slug: settings.workspaceSlug, token: token)
    }

    /// Tema efectivo: predefinido + overrides de color del usuario.
    var theme: Theme {
        var theme = Theme.builtin(settings.themeID)
        if let c = Color(hex: settings.accentHex) { theme.accent = c }
        if let c = Color(hex: settings.backgroundHex) { theme.background = c }
        if let c = Color(hex: settings.surfaceHex) { theme.surface = c }
        if let c = Color(hex: settings.cardHex) { theme.card = c }
        return theme
    }

    var visibleProjects: [Project] {
        projects.filter { settings.visibleProjectIDs.contains($0.id) }
    }

    /// Proyecto activo en el panel: el seleccionado si sigue visible, si no el primero.
    var selectedProject: Project? {
        visibleProjects.first { $0.id == selectedProjectID } ?? visibleProjects.first
    }

    var selectedProjectModules: [Module] {
        guard let project = selectedProject else { return [] }
        return (modulesByProject[project.id] ?? [])
            .filter { $0.status != "cancelled" }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    var selectedProjectCycles: [Cycle] {
        guard let project = selectedProject else { return [] }
        return (cyclesByProject[project.id] ?? [])
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    /// Estados activos del proyecto seleccionado → columnas del kanban.
    var kanbanStates: [WorkItemState] {
        guard let project = selectedProject else { return [] }
        return (statesByProject[project.id] ?? [])
            .filter(\.isActive)
            .sorted { $0.sequence < $1.sequence }
    }

    /// Todos los estados del proyecto seleccionado, incluidos Done/Cancelled:
    /// los menús de cambio de estado deben poder cerrar tareas.
    var allStates: [WorkItemState] {
        guard let project = selectedProject else { return [] }
        return (statesByProject[project.id] ?? []).sorted { $0.sequence < $1.sequence }
    }

    /// Tareas de una columna: proyecto seleccionado + filtros de módulo,
    /// ciclo, "solo mías" y búsqueda.
    func kanbanItems(in state: WorkItemState) -> [WorkItem] {
        guard let project = selectedProject else { return [] }
        let items = cycleFiltered(moduleFiltered(displayedItems(for: project).filter { $0.state == state.id }))
        return searchFiltered(priorityFiltered(items), project: project)
    }

    /// Tareas del cronograma (gantt): misma cadena de filtros que el kanban
    /// (módulo → ciclo → "solo mías" → prioridad → búsqueda), sin partir por estado.
    var ganttItems: [WorkItem] {
        guard let project = selectedProject else { return [] }
        let items = cycleFiltered(moduleFiltered(displayedItems(for: project)))
        return searchFiltered(priorityFiltered(items), project: project)
    }

    private func priorityFiltered(_ items: [WorkItem]) -> [WorkItem] {
        guard let priority = priorityFilter else { return items }
        return items.filter { $0.priority == priority }
    }

    /// Filtro por texto sobre el nombre y el identificador ("ROMAN-12").
    private func searchFiltered(_ items: [WorkItem], project: Project) -> [WorkItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || "\(project.identifier)-\($0.sequenceId)".localizedCaseInsensitiveContains(query)
        }
    }

    func workItem(id: String) -> WorkItem? {
        guard let project = selectedProject else { return nil }
        return itemsByProject[project.id]?.first { $0.id == id }
    }

    /// Tareas activas (ni completadas ni canceladas) de un proyecto,
    /// filtradas por asignación si procede, ordenadas por estado > prioridad > número.
    func displayedItems(for project: Project) -> [WorkItem] {
        let states = statesByProject[project.id] ?? []
        let stateByID = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        return activeItems(for: project, onlyMine: settings.onlyMine).sorted {
            let l = (stateByID[$0.state]?.groupRank ?? 9, $0.priorityRank, $0.sequenceId)
            let r = (stateByID[$1.state]?.groupRank ?? 9, $1.priorityRank, $1.sequenceId)
            return l < r
        }
    }

    private func activeItems(for project: Project, onlyMine: Bool) -> [WorkItem] {
        let states = statesByProject[project.id] ?? []
        let stateByID = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        var items = (itemsByProject[project.id] ?? []).filter {
            stateByID[$0.state]?.isActive ?? true
        }
        if onlyMine, let me = myUserID {
            items = items.filter { $0.assignees.contains(me) }
        }
        return items
    }

    private func moduleFiltered(_ items: [WorkItem]) -> [WorkItem] {
        guard let moduleID = selectedModuleID else { return items }
        let ids = moduleItemIDs[moduleID] ?? []
        return items.filter { ids.contains($0.id) }
    }

    private func cycleFiltered(_ items: [WorkItem]) -> [WorkItem] {
        guard let cycleID = selectedCycleID else { return items }
        let ids = cycleItemIDs[cycleID] ?? []
        return items.filter { ids.contains($0.id) }
    }

    /// Tareas del proyecto/módulo/ciclo actual que el filtro "solo mías" está ocultando.
    var kanbanHiddenCount: Int {
        guard settings.onlyMine, let project = selectedProject else { return 0 }
        let all = cycleFiltered(moduleFiltered(activeItems(for: project, onlyMine: false))).count
        let shown = cycleFiltered(moduleFiltered(activeItems(for: project, onlyMine: true))).count
        return all - shown
    }

    var badgeCount: Int {
        switch settings.badgeMode {
        case "hidden":
            0
        case "urgent":
            visibleProjects.reduce(0) { total, project in
                total + displayedItems(for: project).count { $0.priority == "urgent" }
            }
        case "overdue":
            {
                let today = GanttLayout.isoString(Date(), calendar: .current)
                return visibleProjects.reduce(0) { total, project in
                    total + displayedItems(for: project).count {
                        if let target = $0.targetDate { target < today } else { false }
                    }
                }
            }()
        default:
            visibleProjects.reduce(0) { $0 + displayedItems(for: $1).count }
        }
    }

    func state(of item: WorkItem) -> WorkItemState? {
        statesByProject[item.project]?.first { $0.id == item.state }
    }

    /// Módulo al que pertenece la tarea (solo resuelto para el proyecto seleccionado).
    func module(for item: WorkItem) -> Module? {
        selectedProjectModules.first { moduleItemIDs[$0.id]?.contains(item.id) == true }
    }

    func member(id: String) -> UserLite? {
        membersByProject.values.lazy.compactMap { members in
            members.first { $0.id == id }
        }.first
    }

    /// Asignados de una tarea resueltos contra los members cacheados; un id
    /// desconocido (miembro fuera del proyecto) degrada a UserLite sin nombre.
    func assignees(for item: WorkItem) -> [UserLite] {
        let members = membersByProject[item.project] ?? []
        return item.assignees.map { id in
            members.first { $0.id == id } ?? member(id: id) ?? UserLite(id: id, displayName: nil)
        }
    }

    /// Ciclo al que pertenece la tarea (solo resuelto para el proyecto seleccionado).
    func cycle(for item: WorkItem) -> Cycle? {
        selectedProjectCycles.first { cycleItemIDs[$0.id]?.contains(item.id) == true }
    }

    /// Comentarios de una tarea, bajo demanda (no se cachean: el popover es efímero).
    func comments(for item: WorkItem) async -> [Comment] {
        guard let client else { return [] }
        do {
            return try await client.comments(projectID: item.project, itemID: item.id)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func labels(for item: WorkItem) -> [WorkItemLabel] {
        let catalog = labelsByProject[item.project] ?? []
        return item.labels.compactMap { id in catalog.first { $0.id == id } }
    }

    func webURL(for item: WorkItem, in project: Project) -> URL? {
        URL(string: "\(settings.normalizedBaseURL)/\(settings.workspaceSlug)/browse/\(project.identifier)-\(item.sequenceId)/")
    }

    // MARK: - Carga de datos

    func refresh() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if myUserID == nil { myUserID = try await client.me().id }
            projects = try await client.projects()
            let portfolioProjectIDs = Set(portfolio.filter { !$0.archived }.map(\.plane.projectId))
            for project in projects {
                let visible = settings.visibleProjectIDs.contains(project.id)
                guard visible || portfolioProjectIDs.contains(project.id) else { continue }
                if statesByProject[project.id] == nil {
                    statesByProject[project.id] = try await client.states(projectID: project.id)
                        .sorted { $0.sequence < $1.sequence }
                }
                if labelsByProject[project.id] == nil {
                    labelsByProject[project.id] = try await client.labels(projectID: project.id)
                }
                if membersByProject[project.id] == nil {
                    membersByProject[project.id] = try await client.members(projectID: project.id)
                }
                let previous = itemsByProject[project.id]
                let fresh = try await client.workItems(projectID: project.id)
                itemsByProject[project.id] = fresh
                if visible { notifyDiffs(project: project, old: previous, new: fresh) }
            }
            await loadModules(force: true)
            await loadModuleMemberships(force: true)
            await loadCycles(force: true)
            await loadCycleMemberships(force: true)
            await loadPortfolioMemberships()
            notifyDueSoon()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Carga (con caché) los módulos del proyecto seleccionado.
    func loadModules(force: Bool = false) async {
        guard let client, let project = selectedProject else { return }
        guard force || modulesByProject[project.id] == nil else { return }
        do {
            modulesByProject[project.id] = try await client.modules(projectID: project.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Carga (con caché) los ciclos del proyecto seleccionado.
    func loadCycles(force: Bool = false) async {
        guard let client, let project = selectedProject else { return }
        guard force || cyclesByProject[project.id] == nil else { return }
        do {
            cyclesByProject[project.id] = try await client.cycles(projectID: project.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Carga (con caché) los IDs de tareas del ciclo seleccionado.
    func loadCycleItems(force: Bool = false) async {
        guard let client, let project = selectedProject, let cycleID = selectedCycleID else { return }
        guard force || cycleItemIDs[cycleID] == nil else { return }
        do {
            let items = try await client.cycleWorkItems(projectID: project.id, cycleID: cycleID)
            cycleItemIDs[cycleID] = Set(items.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Carga (con caché) los IDs de tareas del módulo seleccionado.
    func loadModuleItems(force: Bool = false) async {
        guard let client, let project = selectedProject, let moduleID = selectedModuleID else { return }
        guard force || moduleItemIDs[moduleID] == nil else { return }
        do {
            let items = try await client.moduleWorkItems(projectID: project.id, moduleID: moduleID)
            moduleItemIDs[moduleID] = Set(items.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Carga la pertenencia tarea→ciclo de todos los ciclos del proyecto
    /// seleccionado (alimenta tanto el filtro como el chip de ciclo en las cards).
    func loadCycleMemberships(force: Bool = false) async {
        guard let client, let project = selectedProject else { return }
        for cycle in selectedProjectCycles {
            if !force, cycleItemIDs[cycle.id] != nil { continue }
            do {
                let items = try await client.cycleWorkItems(projectID: project.id, cycleID: cycle.id)
                cycleItemIDs[cycle.id] = Set(items.map(\.id))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Carga la pertenencia tarea→módulo de todos los módulos del proyecto
    /// seleccionado (alimenta tanto el filtro como el chip de módulo en las cards).
    func loadModuleMemberships(force: Bool = false) async {
        guard let client, let project = selectedProject else { return }
        for module in selectedProjectModules {
            if !force, moduleItemIDs[module.id] != nil { continue }
            do {
                let items = try await client.moduleWorkItems(projectID: project.id, moduleID: module.id)
                moduleItemIDs[module.id] = Set(items.map(\.id))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Portafolio

    /// Vigila ~/.kodo/portfolio: kodo publica cada ficha con un rename atómico,
    /// que cuenta como escritura del directorio.
    private func watchPortfolio() {
        let directory = Portfolio.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        portfolio = Portfolio.load(from: directory)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.portfolio = Portfolio.load(from: directory)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        portfolioWatcher = source
    }

    /// Módulo de Plane al que apunta la ficha (se resuelve por nombre).
    func portfolioModule(for entry: PortfolioEntry) -> Module? {
        guard let name = entry.plane.module else { return nil }
        return modulesByProject[entry.plane.projectId]?.first { $0.name == name }
    }

    /// Carga la pertenencia tarea→módulo de las fichas activas que apuntan a un
    /// módulo. Los del proyecto seleccionado ya los refrescó loadModuleMemberships.
    private func loadPortfolioMemberships() async {
        guard let client else { return }
        for entry in portfolio where !entry.archived && entry.plane.module != nil {
            let projectID = entry.plane.projectId
            if projectID == selectedProject?.id { continue }
            do {
                if modulesByProject[projectID] == nil {
                    modulesByProject[projectID] = try await client.modules(projectID: projectID)
                }
                guard let module = portfolioModule(for: entry) else { continue }
                let items = try await client.moduleWorkItems(projectID: projectID, moduleID: module.id)
                moduleItemIDs[module.id] = Set(items.map(\.id))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Contadores de la ficha; nil mientras sus datos de Plane no estén cargados
    /// (o si el módulo que nombra no existe en el proyecto).
    func portfolioStats(for entry: PortfolioEntry) -> Portfolio.Stats? {
        let projectID = entry.plane.projectId
        guard let items = itemsByProject[projectID], let states = statesByProject[projectID] else { return nil }
        var memberIDs: Set<String>?
        if entry.plane.module != nil {
            guard let module = portfolioModule(for: entry), let ids = moduleItemIDs[module.id] else { return nil }
            memberIDs = ids
        }
        return Portfolio.stats(
            items: items, states: states, memberIDs: memberIDs,
            todayISO: GanttLayout.isoString(Date(), calendar: .current)
        )
    }

    /// Abre las tareas de la ficha en el tablero (kanban o gantt), filtradas
    /// por su módulo. Si el proyecto estaba oculto, lo hace visible.
    func openPortfolio(_ entry: PortfolioEntry, mode: String = "kanban") {
        let projectID = entry.plane.projectId
        settings.visibleProjectIDs.insert(projectID)
        selectedProjectID = projectID
        selectedModuleID = portfolioModule(for: entry)?.id
        settings.boardMode = mode
    }

    func setPortfolioArchived(_ entry: PortfolioEntry, archived: Bool) {
        do {
            try Portfolio.setArchived(archived, slug: entry.slug, in: Portfolio.directory)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Avisa de tareas que vencen hoy o mañana (una vez por tarea y fecha;
    /// las claves ya avisadas se persisten en UserDefaults y se podan al pasar
    /// la fecha). Corre tras cada refresh: el cambio de día lo cubre el
    /// refresh loop sin necesitar un timer propio.
    private func notifyDueSoon() {
        guard settings.notifyDueSoon else { return }
        let formatter = GanttLayout.dayFormatter(calendar: .current)
        let today = formatter.string(from: Date())
        let tomorrow = formatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let defaults = UserDefaults.standard
        var notified = DueSoon.prune(
            Set(defaults.stringArray(forKey: "dueNotifiedKeys") ?? []),
            todayISO: today
        )
        for project in visibleProjects {
            let items = activeItems(for: project, onlyMine: settings.onlyMine)
            for alert in DueSoon.compute(
                projectIdentifier: project.identifier, items: items,
                todayISO: today, tomorrowISO: tomorrow, alreadyNotified: notified
            ) {
                notified.insert(alert.dueKey)
                let url = items.first { $0.id == alert.itemID }.flatMap { webURL(for: $0, in: project) }
                Notifier.shared.notify(title: alert.title, body: alert.body, url: url)
            }
        }
        defaults.set(Array(notified), forKey: "dueNotifiedKeys")
    }

    /// Notifica difs entre refreshes: tareas nuevas o recién asignadas a mí y
    /// cambios de estado hechos fuera de la app. Los cambios locales no generan
    /// dif porque la actualización optimista ya mutó el caché antes del refresh.
    /// Sin baseline previa (arranque, proyecto recién visible) no se notifica.
    private func notifyDiffs(project: Project, old: [WorkItem]?, new: [WorkItem]) {
        guard settings.notifyChanges, let old else { return }
        let states = statesByProject[project.id] ?? []
        let alerts = RefreshDiff.compute(
            projectIdentifier: project.identifier,
            old: old,
            new: new,
            myUserID: myUserID,
            stateNames: Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0.name) })
        )
        for alert in alerts {
            let url = new.first { $0.id == alert.itemID }.flatMap { webURL(for: $0, in: project) }
            Notifier.shared.notify(title: alert.title, body: alert.body, url: url)
        }
    }

    /// Crea una tarea con ese título en el proyecto seleccionado, asignada a mí
    /// (sin asignar desaparecería con el filtro «solo mías»). Si hay un módulo
    /// filtrado, la añade a ese módulo para que el filtro no la oculte.
    /// El POST acepta `priority` y `labels` directamente (verificado con curl).
    func createWorkItem(named name: String, priority: String? = nil, labelIDs: [String] = []) async -> Bool {
        guard let client, let project = selectedProject else { return false }
        var fields: [String: any Sendable] = ["name": name]
        if let me = myUserID { fields["assignees"] = [me] }
        if let priority { fields["priority"] = priority }
        if !labelIDs.isEmpty { fields["labels"] = labelIDs }
        do {
            let item = try await client.createWorkItem(projectID: project.id, fields: fields)
            itemsByProject[project.id, default: []].append(item)
            if let moduleID = selectedModuleID {
                try await client.addToModule(projectID: project.id, moduleID: moduleID, itemID: item.id)
                moduleItemIDs[moduleID, default: []].insert(item.id)
            }
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func changeState(of item: WorkItem, to newState: WorkItemState) async {
        await update(item, fields: ["state": newState.id]) { $0.state = newState.id }
    }

    /// Reprograma fechas (drag/resize en el gantt); solo envía las que cambian.
    func changeDates(of item: WorkItem, start: String? = nil, target: String? = nil) async {
        var fields: [String: any Sendable] = [:]
        if let start { fields["start_date"] = start }
        if let target { fields["target_date"] = target }
        guard !fields.isEmpty else { return }
        await update(item, fields: fields) {
            if let start { $0.startDate = start }
            if let target { $0.targetDate = target }
        }
    }

    func changePriority(of item: WorkItem, to priority: String) async {
        await update(item, fields: ["priority": priority]) { $0.priority = priority }
    }

    func toggleLabel(_ label: WorkItemLabel, on item: WorkItem) async {
        var ids = item.labels
        if let idx = ids.firstIndex(of: label.id) { ids.remove(at: idx) } else { ids.append(label.id) }
        await update(item, fields: ["labels": ids]) { $0.labels = ids }
    }

    func toggleAssignee(_ member: UserLite, on item: WorkItem) async {
        var ids = item.assignees
        if let idx = ids.firstIndex(of: member.id) { ids.remove(at: idx) } else { ids.append(member.id) }
        await update(item, fields: ["assignees": ids]) { $0.assignees = ids }
    }

    /// PATCH con actualización optimista: aplica `apply` al item local, envía
    /// `fields` a la API y restaura el estado previo si la petición falla.
    private func update(_ item: WorkItem, fields: [String: any Sendable], apply: (inout WorkItem) -> Void) async {
        guard let client else { return }
        let projectID = item.project
        let backup = itemsByProject[projectID]
        if let idx = itemsByProject[projectID]?.firstIndex(where: { $0.id == item.id }) {
            apply(&itemsByProject[projectID]![idx])
        }
        do {
            try await client.updateWorkItem(projectID: projectID, itemID: item.id, fields: fields)
            lastError = nil
        } catch {
            itemsByProject[projectID] = backup
            lastError = error.localizedDescription
        }
    }

    func tokenSaved() {
        cachedToken = Keychain.readToken()
        hasToken = cachedToken?.isEmpty == false
        myUserID = nil
        statesByProject = [:]
        Task { await refresh() }
    }

    private func startAutoRefresh() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = self?.settings.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }
}
