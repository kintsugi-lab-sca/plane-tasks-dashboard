import Testing
@testable import MyTasks

/// Avisos de vencimiento (DueSoon.compute y DueSoon.prune son puros).
struct DueSoonTests {
    private let today = "2026-07-24"
    private let tomorrow = "2026-07-25"

    private func makeItem(
        id: String = "i1",
        name: String = "Tarea",
        seq: Int = 1,
        targetDate: String? = nil
    ) -> WorkItem {
        WorkItem(
            id: id, name: name, priority: "none", sequenceId: seq, state: "s1",
            assignees: [], labels: [], project: "p1",
            startDate: nil, targetDate: targetDate, descriptionHtml: nil
        )
    }

    private func compute(_ items: [WorkItem], notified: Set<String> = []) -> [DueSoon.Alert] {
        DueSoon.compute(
            projectIdentifier: "ROMAN", items: items,
            todayISO: today, tomorrowISO: tomorrow, alreadyNotified: notified
        )
    }

    @Test func venceHoy() {
        let alerts = compute([makeItem(id: "a", name: "Entrega", seq: 4, targetDate: today)])
        #expect(alerts == [DueSoon.Alert(
            itemID: "a", title: "Vence hoy", body: "ROMAN-4 · Entrega", dueKey: "a|2026-07-24"
        )])
    }

    @Test func venceManana() {
        let alerts = compute([makeItem(id: "b", targetDate: tomorrow)])
        #expect(alerts.first?.title == "Vence mañana")
    }

    @Test func otrasFechasNoAvisan() {
        let items = [
            makeItem(id: "pasada", targetDate: "2026-07-20"),
            makeItem(id: "lejana", targetDate: "2026-08-01"),
            makeItem(id: "sinFecha", targetDate: nil),
        ]
        #expect(compute(items).isEmpty)
    }

    @Test func yaAvisadaNoRepite() {
        let items = [makeItem(id: "a", targetDate: today)]
        #expect(compute(items, notified: ["a|2026-07-24"]).isEmpty)
    }

    @Test func reprogramadaVuelveAAvisar() {
        // Avisada cuando vencía el 23; reprogramada al 24 → clave nueva, avisa.
        let items = [makeItem(id: "a", targetDate: today)]
        let alerts = compute(items, notified: ["a|2026-07-23"])
        #expect(alerts.count == 1)
    }

    @Test func pruneEliminaFechasPasadasYMalformadas() {
        let keys: Set<String> = ["a|2026-07-23", "b|2026-07-24", "c|2026-07-25", "sinSeparador"]
        #expect(DueSoon.prune(keys, todayISO: today) == ["b|2026-07-24", "c|2026-07-25"])
    }
}
