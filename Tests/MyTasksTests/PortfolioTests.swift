import Foundation
import Testing
@testable import MyTasks

/// Portafolio: decodificación de la ficha de kodo, contadores y fechas (puro).
struct PortfolioTests {
    private let today = "2026-11-12"

    /// Shape real de `kodo portfolio show`.
    private let fixture = """
    {
      "schema_version": 1,
      "slug": "aparcago",
      "name": "Aparca&Go",
      "plane": { "project_id": "p1", "module": "Aparca&Go" },
      "archived": false,
      "status": "waiting",
      "headline": "Pendiente de validación del cliente",
      "next_step": "Revisar GA4",
      "waiting_on": "Pau",
      "blockers": ["Acceso a GA4"],
      "dates": [{ "date": "2026-12-01", "label": "Entrega" }],
      "steps": [{ "at": "2026-11-12T17:29:01.817Z", "text": "Desplegado", "source": "ROMAN-9" }],
      "updated_at": "2026-11-12T17:29:01.817Z",
      "updated_by": "ROMAN-9",
      "campo_futuro": 42
    }
    """

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "mytasks-portfolio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeItem(
        id: String, state: String, targetDate: String? = nil, completedAt: String? = nil
    ) -> WorkItem {
        WorkItem(
            id: id, name: "Tarea", priority: "none", sequenceId: 1, state: state,
            assignees: [], labels: [], project: "p1",
            startDate: nil, targetDate: targetDate, descriptionHtml: nil, completedAt: completedAt
        )
    }

    private let states = [
        WorkItemState(id: "todo", name: "Todo", color: "#000000", group: "unstarted", sequence: 1),
        WorkItemState(id: "doing", name: "Doing", color: "#000000", group: "started", sequence: 2),
        WorkItemState(id: "review", name: "In Review", color: "#000000", group: "started", sequence: 2.5),
        WorkItemState(id: "done", name: "Done", color: "#000000", group: "completed", sequence: 3),
        WorkItemState(id: "no", name: "Cancelled", color: "#000000", group: "cancelled", sequence: 4),
    ]

    @Test func cargaFichasYOmiteLasCorruptas() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        try Data("{ roto".utf8).write(to: dir.appending(path: "roto.json"))
        try Data("x".utf8).write(to: dir.appending(path: "notas.txt"))

        let entries = Portfolio.load(from: dir)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.plane.projectId == "p1")
        #expect(entry.plane.module == "Aparca&Go")
        #expect(entry.nextStep == "Revisar GA4")
        #expect(entry.steps.first?.source == "ROMAN-9")
        #expect(entry.events == nil)
    }

    @Test func decodificaReunionesYCorreos() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let withEvents = fixture.replacingOccurrences(
            of: "\"campo_futuro\": 42",
            with: "\"events\": [{ \"kind\": \"meeting\", \"date\": \"2026-11-12\", \"title\": \"aparca&go web\", \"summary\": null, \"ref\": \"m-1\" }]"
        )
        try Data(withEvents.utf8).write(to: dir.appending(path: "aparcago.json"))
        let event = try #require(Portfolio.load(from: dir).first?.events?.first)
        #expect(event.kind == "meeting")
        #expect(event.title == "aparca&go web")
        #expect(event.summary == nil)
    }

    @Test func directorioInexistenteDaListaVacia() {
        #expect(Portfolio.load(from: URL(filePath: "/no/existe/portfolio")).isEmpty)
    }

    @Test func archivarConservaElRestoDelFichero() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "aparcago.json")
        try Data(fixture.utf8).write(to: url)

        try Portfolio.setArchived(true, slug: "aparcago", in: dir)

        #expect(Portfolio.load(from: dir).first?.archived == true)
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(raw["campo_futuro"] as? Int == 42)
        #expect(raw["headline"] as? String == "Pendiente de validación del cliente")
    }

    @Test func contadoresPorGrupoDeEstado() {
        let items = [
            makeItem(id: "a", state: "done"),
            makeItem(id: "b", state: "doing", targetDate: "2026-11-20"),
            makeItem(id: "c", state: "todo", targetDate: "2026-11-01"),
            makeItem(id: "d", state: "todo", targetDate: today),
            makeItem(id: "e", state: "no", targetDate: "2026-11-13"),
            makeItem(id: "f", state: "desconocido"),
            makeItem(id: "g", state: "review"),
        ]
        let stats = Portfolio.stats(items: items, states: states, memberIDs: nil, todayISO: today)
        #expect(stats == Portfolio.Stats(done: 1, started: ["doing": 1, "review": 1], todo: 2, overdue: 1, nextDue: today))
        #expect(stats.total == 5)
    }

    @Test func contadoresRestringidosAlModulo() {
        let items = [
            makeItem(id: "a", state: "done"),
            makeItem(id: "b", state: "doing"),
            makeItem(id: "c", state: "todo"),
        ]
        let stats = Portfolio.stats(items: items, states: states, memberIDs: ["a", "c"], todayISO: today)
        #expect(stats == Portfolio.Stats(done: 1, started: [:], todo: 1, overdue: 0, nextDue: nil))
    }

    @Test func proximaFechaEligeLaMasCercana() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        let entry = try #require(Portfolio.load(from: dir).first)

        // Sin datos de Plane: el hito de la ficha.
        #expect(Portfolio.upcoming(entry: entry, stats: nil, todayISO: today)?.label == "Entrega")
        // Un vencimiento de tarea anterior al hito gana.
        let sooner = Portfolio.Stats(nextDue: "2026-11-20")
        #expect(Portfolio.upcoming(entry: entry, stats: sooner, todayISO: today)?.date == "2026-11-20")
        // Un hito ya pasado no cuenta.
        #expect(Portfolio.upcoming(entry: entry, stats: nil, todayISO: "2026-12-02") == nil)
    }

    @Test func agendaMezclaHitosYTareasActivas() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        let entry = try #require(Portfolio.load(from: dir).first)
        let items = [
            makeItem(id: "vencida", state: "todo", targetDate: "2026-11-01"),
            makeItem(id: "mismoDia", state: "doing", targetDate: "2026-12-01"),
            makeItem(id: "hecha", state: "done", targetDate: "2026-11-15"),
            makeItem(id: "sinFecha", state: "todo"),
        ]
        let rows = Portfolio.agenda(entry: entry, items: items, states: states, todayISO: today)
        #expect(rows.map(\.itemID) == ["vencida", nil, "mismoDia"])
        #expect(rows.map(\.overdue) == [true, false, false])
        #expect(rows[1].label == "Entrega")
    }

    @Test func entregadoEnLaUltimaSemana() {
        let items = [
            makeItem(id: "ayer", state: "done", completedAt: "2026-11-11T09:00:00.000000Z"),
            makeItem(id: "limite", state: "done", completedAt: "2026-11-05T23:59:00Z"),
            makeItem(id: "viejo", state: "done", completedAt: "2026-11-04T10:00:00Z"),
            makeItem(id: "sinFecha", state: "done"),
            makeItem(id: "reabierta", state: "doing", completedAt: "2026-11-11T09:00:00Z"),
        ]
        #expect(Portfolio.dayISO(today, minusDays: 7) == "2026-11-05")
        let delivered = Portfolio.delivered(items: items, states: states, sinceISO: "2026-11-05")
        #expect(delivered.map(\.id) == ["ayer", "limite"])
        let stats = Portfolio.stats(items: items, states: states, memberIDs: nil, todayISO: today)
        #expect(stats.done == 4)
        #expect(stats.deliveredRecently == 2)
    }

    @Test func entregasPosterioresALaFichaQuedanSinReflejar() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        // updated_at de la fixture: 2026-11-12T17:29:01.817Z
        let entry = try #require(Portfolio.load(from: dir).first)
        let items = [
            makeItem(id: "antes", state: "done", completedAt: "2026-11-12T17:00:00.000000Z"),
            makeItem(id: "despues", state: "done", completedAt: "2026-11-12T19:30:00.123456+02:00"),
            makeItem(id: "luego", state: "done", completedAt: "2026-11-13T08:00:00Z"),
            makeItem(id: "abierta", state: "doing", completedAt: "2026-11-13T08:00:00Z"),
            makeItem(id: "sinFecha", state: "done"),
        ]
        // 19:30+02:00 son las 17:30Z: posterior a las 17:29Z de la ficha.
        #expect(Portfolio.unreported(entry: entry, items: items, states: states) == 2)
        var stats = Portfolio.Stats()
        stats.unreported = 2
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-13T10:00:00Z"))
        #expect(Portfolio.attention(entry: entry, stats: stats, now: now) == .blocked)
    }

    @Test func nivelDeAtencion() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        func entry(_ patch: [String: String]) throws -> PortfolioEntry {
            var json = fixture
            for (from, to) in patch { json = json.replacingOccurrences(of: from, with: to) }
            try Data(json.utf8).write(to: dir.appending(path: "aparcago.json"))
            return try #require(Portfolio.load(from: dir).first)
        }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-13T10:00:00Z"))
        let noBlockers = ["[\"Acceso a GA4\"]": "[]"]
        let calm = Portfolio.Stats()
        let overdue = Portfolio.Stats(overdue: 2)

        #expect(Portfolio.attention(entry: try entry([:]), stats: calm, now: now) == .blocked)
        #expect(Portfolio.attention(entry: try entry(noBlockers), stats: overdue, now: now) == .overdue)
        #expect(Portfolio.attention(entry: try entry(noBlockers), stats: calm, now: now) == .none)
        #expect(Portfolio.attention(entry: try entry(noBlockers), stats: Portfolio.Stats(unreported: 1), now: now) == .stale)
        #expect(Portfolio.attention(entry: try entry(noBlockers), stats: nil, now: now.addingTimeInterval(9 * 86400)) == .stale)
        let noHeadline = noBlockers.merging(["\"Pendiente de validación del cliente\"": "null"]) { a, _ in a }
        #expect(Portfolio.attention(entry: try entry(noHeadline), stats: calm, now: now) == .stale)
        let paused = ["\"waiting\"": "\"paused\""]
        #expect(Portfolio.attention(entry: try entry(paused), stats: overdue, now: now) == .none)
        #expect(Portfolio.Attention.blocked > .overdue && Portfolio.Attention.overdue > .stale)
    }

    @Test func slugSigueLaReglaDeKodo() {
        #expect(Portfolio.slug(for: "Aparca&Go") == "aparca-go")
        #expect(Portfolio.slug(for: "  Traça Web · Núñez ") == "traca-web-nunez")
        #expect(Portfolio.slug(for: "F2 · Dominio y backoffice (impacts + admin + import Excel)").count <= 40)
        #expect(Portfolio.slug(for: "···") == "")
    }

    @Test func altaCreaFichaLegibleYNoPisaLaExistente() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try Portfolio.create(name: "Traça Web", projectID: "p1", module: "Traça Web", in: dir)
        let second = try Portfolio.create(name: "Traça Web", projectID: "p2", module: nil, in: dir)
        #expect(first == "traca-web")
        #expect(second == "traca-web-2")

        let entries = Portfolio.load(from: dir)
        #expect(entries.count == 2)
        let entry = try #require(entries.first { $0.slug == first })
        #expect(entry.plane == PortfolioEntry.PlaneRef(projectId: "p1", module: "Traça Web"))
        #expect(entry.headline == nil)
        #expect(entry.archived == false)
        #expect(entries.first { $0.slug == second }?.plane.module == nil)
    }

    @Test func slugDeModuloLlevaElProyectoDelante() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let liken = try Portfolio.create(name: "DEV", projectID: "p1", module: "DEV", projectName: "Liken", in: dir)
        let scribba = try Portfolio.create(name: "DEV", projectID: "p2", module: "DEV", projectName: "Scribba", in: dir)
        let whole = try Portfolio.create(name: "Clipping", projectID: "p3", module: nil, projectName: "Clipping", in: dir)
        #expect(liken == "liken-dev")
        #expect(scribba == "scribba-dev")
        #expect(whole == "clipping")
        #expect(Portfolio.load(from: dir).filter { $0.name == "DEV" }.count == 2)
    }

    @Test func enRevisionNoCuentaComoVencida() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        let entry = try #require(Portfolio.load(from: dir).first)
        let items = [
            makeItem(id: "enRevision", state: "review", targetDate: "2026-11-01"),
            makeItem(id: "enCurso", state: "doing", targetDate: "2026-11-01"),
        ]
        // El fixture llama al estado «In Review»; kodo lo declara como «In review».
        let withReview = Portfolio.stats(
            items: items, states: states, memberIDs: nil, todayISO: today, reviewState: "In review"
        )
        #expect(withReview.overdue == 1)
        // Sin estado declarado no se adivina nada: las dos vencen.
        #expect(Portfolio.stats(items: items, states: states, memberIDs: nil, todayISO: today).overdue == 2)

        let rows = Portfolio.agenda(
            entry: entry, items: items, states: states, todayISO: today, reviewState: "In review"
        ).filter { $0.itemID != nil }
        #expect(rows.first { $0.itemID == "enRevision" }?.overdue == false)
        #expect(rows.first { $0.itemID == "enCurso" }?.overdue == true)
        #expect(rows.first { $0.itemID == "enRevision" }?.stateName == "In Review")
        #expect(rows.first { $0.itemID == "enCurso" }?.stateColor == "#000000")
        // Un «Done» que se llamara igual no es revisión: solo cuenta el grupo started.
        let done = WorkItemState(id: "d", name: "In review", color: "#000000", group: "completed", sequence: 9)
        #expect(Portfolio.isReview(done, reviewState: "In review") == false)
    }

    @Test func leeElEstadoDeRevisionDeKodo() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appending(path: "config.json")
        #expect(Portfolio.reviewStateName(kodoConfig: config) == nil)
        try Data(#"{"providers":{"plane":{"states":{"trigger":"Todo","review":"In review","done":"Done"}}}}"#.utf8)
            .write(to: config)
        #expect(Portfolio.reviewStateName(kodoConfig: config) == "In review")
        #expect(Portfolio.kodoStateName("done", kodoConfig: config) == "Done")
        try Data(#"{"providers":{"plane":{}}}"#.utf8).write(to: config)
        #expect(Portfolio.reviewStateName(kodoConfig: config) == nil)
    }

    @Test func estadoDeDestinoAlDarPorHecha() {
        let extra = states + [
            WorkItemState(id: "released", name: "Released", color: "#000000", group: "completed", sequence: 1.5),
        ]
        // El que kodo declara como done, aunque no sea el primero ni coincida en mayúsculas.
        #expect(Portfolio.doneState(in: extra, doneName: "done")?.id == "done")
        // Sin nombre declarado o sin coincidencia: el primer estado completado.
        #expect(Portfolio.doneState(in: extra, doneName: nil)?.id == "released")
        #expect(Portfolio.doneState(in: extra, doneName: "Cerrada")?.id == "released")
        // Nunca un estado de otro grupo, aunque se llame igual.
        #expect(Portfolio.doneState(in: [states[0]], doneName: "Todo") == nil)
    }

    @Test func hitosCumplidosYVencidos() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "aparcago.json")
        let dated = fixture.replacingOccurrences(
            of: "[{ \"date\": \"2026-12-01\", \"label\": \"Entrega\" }]",
            with: "[{ \"date\": \"2026-11-10\", \"label\": \"Demo\" }, { \"date\": \"2026-11-12\", \"label\": \"Preview\" }]"
        ).replacingOccurrences(of: "[\"Acceso a GA4\"]", with: "[]")
        try Data(dated.utf8).write(to: url)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-12T10:00:00Z"))
        func load() throws -> PortfolioEntry { try #require(Portfolio.load(from: dir).first) }

        // Un hito pendiente con la fecha pasada cuenta como vencido y pide atención.
        var rows = Portfolio.agenda(entry: try load(), items: [], states: states, todayISO: today)
        #expect(rows.map(\.overdue) == [true, false])
        #expect(Portfolio.attention(entry: try load(), stats: Portfolio.Stats(), now: now) == .overdue)

        try Portfolio.setMilestoneDone(true, date: "2026-11-10", label: "Demo", slug: "aparcago", in: dir, now: now)
        try Portfolio.setMilestoneDone(true, date: today, label: "Preview", slug: "aparcago", in: dir, now: now)
        var entry = try load()
        #expect(entry.dates.map(\.isDone) == [true, true])
        #expect(entry.updatedBy == "mytasks")
        // Cumplidos: siguen en la ficha como historia, sin vencer, y dejan de pedir atención.
        rows = Portfolio.agenda(entry: entry, items: [], states: states, todayISO: today)
        #expect(rows.map(\.done) == [true, true])
        #expect(rows.map(\.overdue) == [false, false])
        #expect(Portfolio.attention(entry: entry, stats: Portfolio.Stats(), now: now) == .none)
        #expect(Portfolio.upcoming(entry: entry, stats: nil, todayISO: today) == nil)
        #expect(DueSoon.milestoneAlerts(
            entries: [entry], todayISO: today, tomorrowISO: "2026-11-13", alreadyNotified: []
        ).isEmpty)
        // La agenda conjunta solo enseña el cumplido de hoy; el pasado no vuelve como día.
        let week = Portfolio.weekAgenda([(entry: entry, rows: rows)], todayISO: today)
        #expect(week.map(\.date) == [today])
        // Pasada una semana, el cumplido antiguo deja de listarse.
        #expect(Portfolio.agenda(entry: entry, items: [], states: states, todayISO: "2026-11-18").map(\.label) == ["Preview"])

        try Portfolio.setMilestoneDone(false, date: today, label: "Preview", slug: "aparcago", in: dir, now: now)
        entry = try load()
        #expect(entry.dates.map(\.isDone) == [true, false])
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(raw["campo_futuro"] as? Int == 42)
        #expect(throws: (any Error).self) {
            try Portfolio.setMilestoneDone(true, date: "2026-01-01", label: "No existe", slug: "aparcago", in: dir)
        }
    }

    @Test func agendaConjuntaAgrupaVencidoYPorDia() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(fixture.utf8).write(to: dir.appending(path: "aparcago.json"))
        let aparca = try #require(Portfolio.load(from: dir).first)
        func row(_ date: String, _ label: String, item: String? = nil, overdue: Bool = false) -> Portfolio.AgendaRow {
            Portfolio.AgendaRow(date: date, label: label, itemID: item, overdue: overdue)
        }
        let days = Portfolio.weekAgenda([
            (entry: aparca, rows: [
                row("2026-11-01", "Tarea vencida", item: "t1", overdue: true),
                row("2026-11-14", "Tarea del 14", item: "t2"),
                row("2026-11-14", "Hito del 14"),
                row("2026-12-01", "Fuera de la ventana"),
            ]),
        ], todayISO: today, days: 14)
        #expect(days.map(\.date) == [nil, "2026-11-14"])
        #expect(days[0].rows.map(\.row.label) == ["Tarea vencida"])
        // Mismo día y misma ficha: el hito antes que la tarea.
        #expect(days[1].rows.map(\.row.label) == ["Hito del 14", "Tarea del 14"])
        #expect(days[1].rows.first?.entryName == "Aparca&Go")
        #expect(Portfolio.weekAgenda([], todayISO: today).isEmpty)
    }

    @Test func editarSituacionAManoConservaElResto() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "aparcago.json")
        try Data(fixture.utf8).write(to: url)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-17T09:00:00Z"))

        let edited = Portfolio.Situation(
            headline: "  Validado\npor el cliente ", nextStep: "", waitingOn: "Pau", status: "on_track"
        )
        try Portfolio.updateSituation(edited, slug: "aparcago", in: dir, now: now)

        let entry = try #require(Portfolio.load(from: dir).first)
        #expect(entry.headline == "Validado por el cliente")
        #expect(entry.nextStep == nil)
        #expect(entry.waitingOn == "Pau")
        #expect(entry.status == "on_track")
        #expect(entry.updatedBy == "mytasks")
        #expect(Portfolio.ageInDays(updatedAt: entry.updatedAt, now: now) == 0)
        #expect(entry.blockers == ["Acceso a GA4"])
        #expect(entry.steps.count == 1)
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(raw["campo_futuro"] as? Int == 42)

        // Un estado fuera del vocabulario se guarda como «sin estado».
        try Portfolio.updateSituation(Portfolio.Situation(status: "verde"), slug: "aparcago", in: dir, now: now)
        #expect(Portfolio.load(from: dir).first?.status == nil)
        #expect(Portfolio.Situation(entry) == Portfolio.Situation(
            headline: "Validado por el cliente", nextStep: "", waitingOn: "Pau", status: "on_track"
        ))
    }

    @Test func ultimoBarrido() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Portfolio.lastSweep(in: dir) == nil)
        try Data("2026-11-10\n".utf8).write(to: dir.appending(path: ".last-sweep"))
        #expect(Portfolio.lastSweep(in: dir) == "2026-11-10")
        #expect(Portfolio.daysBetween("2026-11-10", today) == 2)
        try Data("ayer".utf8).write(to: dir.appending(path: ".last-sweep"))
        #expect(Portfolio.lastSweep(in: dir) == nil)
        // La marca no es una ficha.
        #expect(Portfolio.load(from: dir).isEmpty)
    }

    @Test func avisosDeHitosDeFicha() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dated = fixture.replacingOccurrences(of: "\"date\": \"2026-12-01\"", with: "\"date\": \"2026-11-13\"")
        try Data(dated.utf8).write(to: dir.appending(path: "aparcago.json"))
        let entries = Portfolio.load(from: dir)

        let tomorrow = DueSoon.milestoneAlerts(
            entries: entries, todayISO: today, tomorrowISO: "2026-11-13", alreadyNotified: []
        )
        #expect(tomorrow.map(\.title) == ["Hito mañana"])
        #expect(tomorrow.first?.body == "Aparca&Go · Entrega")
        let key = try #require(tomorrow.first?.dueKey)
        #expect(key == "hito:aparcago:Entrega|2026-11-13")
        // Ya avisado → nada; y la clave sobrevive a la poda hasta que pasa la fecha.
        #expect(DueSoon.milestoneAlerts(
            entries: entries, todayISO: today, tomorrowISO: "2026-11-13", alreadyNotified: [key]
        ).isEmpty)
        #expect(DueSoon.prune([key], todayISO: "2026-11-13") == [key])
        #expect(DueSoon.prune([key], todayISO: "2026-11-14").isEmpty)
        // Otro día → nada.
        #expect(DueSoon.milestoneAlerts(
            entries: entries, todayISO: "2026-11-20", tomorrowISO: "2026-11-21", alreadyNotified: []
        ).isEmpty)
    }

    @Test func columnasDelDetalleSegunElAncho() {
        #expect(PortfolioDetailView.columnCount(width: 600, fontScale: 1) == 1)
        #expect(PortfolioDetailView.columnCount(width: 1000, fontScale: 1) == 2)
        #expect(PortfolioDetailView.columnCount(width: 2000, fontScale: 1) == 3)
        // Con la letra más grande hace falta más ancho para el mismo reparto.
        #expect(PortfolioDetailView.columnCount(width: 1000, fontScale: 1.3) == 1)
    }

    @Test func antiguedadEnDias() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-11-22T18:00:00Z"))
        #expect(Portfolio.ageInDays(updatedAt: "2026-11-12T17:29:01.817Z", now: now) == 10)
        #expect(Portfolio.ageInDays(updatedAt: "2026-11-22T10:00:00Z", now: now) == 0)
        #expect(Portfolio.ageInDays(updatedAt: "ayer", now: now) == nil)
    }
}
