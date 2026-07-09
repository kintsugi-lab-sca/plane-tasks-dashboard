import Testing
@testable import MyTasks

/// Difs notificables entre refreshes (RefreshDiff.compute es puro).
struct RefreshDiffTests {
    private let me = "user-me"

    private func makeItem(
        id: String = "i1",
        name: String = "Tarea",
        seq: Int = 1,
        state: String = "s1",
        assignees: [String] = []
    ) -> WorkItem {
        WorkItem(
            id: id, name: name, priority: "none", sequenceId: seq, state: state,
            assignees: assignees, labels: [], project: "p1",
            startDate: nil, targetDate: nil, descriptionHtml: nil
        )
    }

    private func compute(old: [WorkItem], new: [WorkItem], stateNames: [String: String] = [:]) -> [RefreshDiff.Alert] {
        RefreshDiff.compute(projectIdentifier: "ROMAN", old: old, new: new, myUserID: me, stateNames: stateNames)
    }

    @Test func nuevaTareaAsignadaAMi() {
        let alerts = compute(old: [], new: [makeItem(id: "n1", name: "Nueva", seq: 7, assignees: [me])])
        #expect(alerts == [RefreshDiff.Alert(itemID: "n1", title: "Nueva tarea asignada", body: "ROMAN-7 · Nueva")])
    }

    @Test func nuevaTareaSinAsignarNoNotifica() {
        // Caso integración externa: crea tareas sin asignar.
        #expect(compute(old: [], new: [makeItem(id: "n1")]).isEmpty)
    }

    @Test func reasignacionAMi() {
        let old = [makeItem(id: "i1", name: "Mía ahora", seq: 3, assignees: ["otra"])]
        let new = [makeItem(id: "i1", name: "Mía ahora", seq: 3, assignees: ["otra", me])]
        #expect(compute(old: old, new: new) == [
            RefreshDiff.Alert(itemID: "i1", title: "Tarea asignada a ti", body: "ROMAN-3 · Mía ahora")
        ])
    }

    @Test func cambioDeEstadoResuelveNombre() {
        let old = [makeItem(id: "i1", name: "Movida", seq: 5, state: "s1")]
        let new = [makeItem(id: "i1", name: "Movida", seq: 5, state: "s2")]
        #expect(compute(old: old, new: new, stateNames: ["s2": "In review"]) == [
            RefreshDiff.Alert(itemID: "i1", title: "ROMAN-5 → In review", body: "Movida")
        ])
    }

    @Test func cambioDeEstadoDesconocido() {
        let alerts = compute(old: [makeItem(state: "s1")], new: [makeItem(state: "s9")])
        #expect(alerts.first?.title == "ROMAN-1 → otro estado")
    }

    @Test func sinCambiosNoNotifica() {
        let items = [makeItem(assignees: [me])]
        #expect(compute(old: items, new: items).isEmpty)
    }

    @Test func cambioDeEstadoEnTareaYaMiaNoDuplicaAsignacion() {
        let old = [makeItem(id: "i1", state: "s1", assignees: [me])]
        let new = [makeItem(id: "i1", state: "s2", assignees: [me])]
        let alerts = compute(old: old, new: new)
        #expect(alerts.count == 1)
        #expect(alerts.first?.title == "ROMAN-1 → otro estado")
    }

    @Test func sinUsuarioNoNotificaAsignaciones() {
        let alerts = RefreshDiff.compute(
            projectIdentifier: "ROMAN",
            old: [],
            new: [makeItem(assignees: ["cualquiera"])],
            myUserID: nil,
            stateNames: [:]
        )
        #expect(alerts.isEmpty)
    }
}
