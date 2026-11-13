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

    private func makeItem(id: String, state: String, targetDate: String? = nil) -> WorkItem {
        WorkItem(
            id: id, name: "Tarea", priority: "none", sequenceId: 1, state: state,
            assignees: [], labels: [], project: "p1",
            startDate: nil, targetDate: targetDate, descriptionHtml: nil
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
        #expect(stats == Portfolio.Stats(done: 1, inProgress: 1, inReview: 1, todo: 2, overdue: 1, nextDue: today))
        #expect(stats.total == 5)
    }

    @Test func contadoresRestringidosAlModulo() {
        let items = [
            makeItem(id: "a", state: "done"),
            makeItem(id: "b", state: "doing"),
            makeItem(id: "c", state: "todo"),
        ]
        let stats = Portfolio.stats(items: items, states: states, memberIDs: ["a", "c"], todayISO: today)
        #expect(stats == Portfolio.Stats(done: 1, inProgress: 0, inReview: 0, todo: 1, overdue: 0, nextDue: nil))
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

    @Test func antiguedadEnDias() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-11-22T18:00:00Z"))
        #expect(Portfolio.ageInDays(updatedAt: "2026-11-12T17:29:01.817Z", now: now) == 10)
        #expect(Portfolio.ageInDays(updatedAt: "2026-11-22T10:00:00Z", now: now) == 0)
        #expect(Portfolio.ageInDays(updatedAt: "ayer", now: now) == nil)
    }
}
