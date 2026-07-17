import Foundation
import Testing

@testable import MyTasks

/// Motor de layout del gantt (GanttLayout.make es puro).
struct GanttLayoutTests {
    private let calendar = Calendar.current
    private var formatter: DateFormatter { GanttLayout.dayFormatter(calendar: calendar) }

    /// Jueves 16 de julio de 2026.
    private var today: Date { formatter.date(from: "2026-07-16")! }

    private func makeItem(
        id: String = "i1",
        seq: Int = 1,
        priority: String = "none",
        start: String? = nil,
        target: String? = nil
    ) -> WorkItem {
        WorkItem(
            id: id, name: "Tarea", priority: priority, sequenceId: seq, state: "s1",
            assignees: [], labels: [], project: "p1",
            startDate: start, targetDate: target, descriptionHtml: nil
        )
    }

    private func layout(_ items: [WorkItem], dayWidth: CGFloat = 10) -> GanttLayout {
        GanttLayout.make(items: items, today: today, dayWidth: dayWidth, calendar: calendar)
    }

    // MARK: - Eje

    @Test func ejeEmpiezaEnLunesYEsMultiploDeSemana() {
        let l = layout([makeItem(start: "2026-07-10", target: "2026-07-20")])
        #expect(calendar.component(.weekday, from: l.firstDay) == 2)
        #expect(l.dayCount % 7 == 0)
        #expect(l.firstDay <= l.today)
        #expect(l.day(l.dayCount - 1) >= l.today)
    }

    @Test func ejeIncluyeTodasLasFechasConMargen() {
        let l = layout([makeItem(start: "2026-06-01", target: "2026-09-15")])
        #expect(l.firstDay <= formatter.date(from: "2026-06-01")!)
        #expect(l.day(l.dayCount - 1) >= formatter.date(from: "2026-09-15")!)
    }

    @Test func fechasAbsurdasNoEstiranElEje() {
        let l = layout([makeItem(target: "2099-01-01")])
        // La fecha lejana se ignora para el rango: el eje queda alrededor de hoy.
        #expect(l.dayCount < 100)
    }

    // MARK: - Clasificación

    @Test func clasificaSegunFechas() {
        let l = layout([
            makeItem(id: "bar", start: "2026-07-10", target: "2026-07-20"),
            makeItem(id: "hito", target: "2026-07-25"),
            makeItem(id: "abierta", start: "2026-07-01"),
            makeItem(id: "sin"),
        ])
        #expect(l.rows.count == 3)
        #expect(l.unscheduled.map(\.id) == ["sin"])
        guard case .bar = l.rows.first(where: { $0.id == "bar" })!.kind else {
            Issue.record("esperaba .bar"); return
        }
        guard case .milestone = l.rows.first(where: { $0.id == "hito" })!.kind else {
            Issue.record("esperaba .milestone"); return
        }
        guard case .openEnded = l.rows.first(where: { $0.id == "abierta" })!.kind else {
            Issue.record("esperaba .openEnded"); return
        }
    }

    @Test func fechasInvertidasSeNormalizan() {
        let l = layout([makeItem(start: "2026-07-20", target: "2026-07-10")])
        guard case let .bar(start, end) = l.rows[0].kind else {
            Issue.record("esperaba .bar"); return
        }
        #expect(start <= end)
    }

    @Test func filasOrdenadasCronologicamente() {
        let l = layout([
            makeItem(id: "b", seq: 2, start: "2026-07-20", target: "2026-07-22"),
            makeItem(id: "a", seq: 1, start: "2026-07-01", target: "2026-07-05"),
        ])
        #expect(l.rows.map(\.id) == ["a", "b"])
    }

    // MARK: - Geometría

    @Test func posicionYAnchoDeBarra() {
        let l = layout([makeItem(start: "2026-07-13", target: "2026-07-15")], dayWidth: 10)
        let frame = l.frame(for: l.rows[0].kind)
        // Barra de 3 días (13, 14 y 15 incluidos) → 30 pt de ancho.
        #expect(frame.width == 30)
        #expect(frame.x == l.x(formatter.date(from: "2026-07-13")!))
        #expect(l.totalWidth == CGFloat(l.dayCount) * 10)
    }

    @Test func barraAbiertaLlegaHastaHoy() {
        let l = layout([makeItem(start: "2026-07-10")], dayWidth: 10)
        let frame = l.frame(for: l.rows[0].kind)
        #expect(frame.x + frame.width == l.x(today) + 10)
    }

    @Test func semanasYMesesCubrenElEje() {
        let l = layout([makeItem(start: "2026-06-20", target: "2026-08-10")], dayWidth: 10)
        #expect(l.weekTicks.count == l.dayCount / 7)
        #expect(l.monthTicks.map(\.width).reduce(0, +) == l.totalWidth)
    }

    // MARK: - Fechas ISO y luminancia

    @Test func isoRoundtrip() {
        let date = GanttLayout.parseDay("2026-07-16", formatter: formatter, calendar: calendar)!
        #expect(GanttLayout.isoString(date, calendar: calendar) == "2026-07-16")
        #expect(GanttLayout.parseDay("no-fecha", formatter: formatter, calendar: calendar) == nil)
        #expect(GanttLayout.parseDay(nil, formatter: formatter, calendar: calendar) == nil)
    }

    @Test func luminanciaDeColores() {
        #expect(GanttLayout.luminance(hex: "#FFFFFF") == 1)
        #expect(GanttLayout.luminance(hex: "#000000") == 0)
        #expect(GanttLayout.luminance(hex: nil) == 0)
        #expect(GanttLayout.luminance(hex: "#FFD700") > 0.55)  // amarillo → texto oscuro
        #expect(GanttLayout.luminance(hex: "#1E40AF") < 0.55)  // azul oscuro → texto claro
    }
}
