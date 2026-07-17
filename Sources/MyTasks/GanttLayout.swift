import Foundation

/// Motor de layout del cronograma (gantt): puro y testeable. Convierte las
/// fechas ISO ("yyyy-MM-dd") de los work items en un eje de días alineado a
/// semana y en posiciones/anchos en puntos. No sabe nada de SwiftUI.
struct GanttLayout {
    struct Row: Identifiable {
        enum Kind {
            /// Con fecha de inicio y límite → barra.
            case bar(start: Date, end: Date)
            /// Solo fecha límite → hito (rombo en esa fecha).
            case milestone(Date)
            /// Solo fecha de inicio → barra abierta desde el inicio hasta hoy.
            case openEnded(start: Date)
        }

        let item: WorkItem
        let kind: Kind
        var id: String { item.id }

        /// Fecha por la que se ordena la fila en el cronograma.
        var sortDate: Date {
            switch kind {
            case let .bar(start, _): start
            case let .milestone(date): date
            case let .openEnded(start): start
            }
        }
    }

    let calendar: Calendar
    /// Primer día del eje (siempre lunes).
    let firstDay: Date
    /// Días totales del eje (múltiplo de 7).
    let dayCount: Int
    let dayWidth: CGFloat
    /// Hoy, normalizado a inicio de día.
    let today: Date
    /// Filas con fecha, ordenadas cronológicamente.
    let rows: [Row]
    /// Tareas sin ninguna fecha (bandeja aparte).
    let unscheduled: [WorkItem]

    /// El eje ignora fechas a más de esta distancia de hoy para no crear un
    /// scroll kilométrico por un dato erróneo; las barras se recortan al borde.
    private static let pastLimitDays = 180
    private static let futureLimitDays = 366

    static func make(
        items: [WorkItem],
        today rawToday: Date = Date(),
        dayWidth: CGFloat,
        calendar: Calendar = .current
    ) -> GanttLayout {
        let today = calendar.startOfDay(for: rawToday)
        let formatter = dayFormatter(calendar: calendar)

        var rows: [Row] = []
        var unscheduled: [WorkItem] = []
        for item in items {
            let start = parseDay(item.startDate, formatter: formatter, calendar: calendar)
            let target = parseDay(item.targetDate, formatter: formatter, calendar: calendar)
            switch (start, target) {
            case let (s?, t?):
                rows.append(Row(item: item, kind: .bar(start: min(s, t), end: max(s, t))))
            case let (nil, t?):
                rows.append(Row(item: item, kind: .milestone(t)))
            case let (s?, nil):
                rows.append(Row(item: item, kind: .openEnded(start: s)))
            case (nil, nil):
                unscheduled.append(item)
            }
        }
        rows.sort {
            ($0.sortDate, $0.item.priorityRank, $0.item.sequenceId)
                < ($1.sortDate, $1.item.priorityRank, $1.item.sequenceId)
        }

        // Rango del eje: todas las fechas (acotadas alrededor de hoy) + margen,
        // arrancando en lunes y con un número de días múltiplo de 7.
        let pastLimit = calendar.date(byAdding: .day, value: -pastLimitDays, to: today)!
        let futureLimit = calendar.date(byAdding: .day, value: futureLimitDays, to: today)!
        var minDate = today
        var maxDate = today
        for row in rows {
            let dates: [Date]
            switch row.kind {
            case let .bar(start, end): dates = [start, end]
            case let .milestone(date): dates = [date]
            case let .openEnded(start): dates = [start]
            }
            for date in dates where date >= pastLimit && date <= futureLimit {
                minDate = min(minDate, date)
                maxDate = max(maxDate, date)
            }
        }
        var firstDay = calendar.date(byAdding: .day, value: -7, to: minDate)!
        while calendar.component(.weekday, from: firstDay) != 2 {  // 2 = lunes
            firstDay = calendar.date(byAdding: .day, value: -1, to: firstDay)!
        }
        let last = calendar.date(byAdding: .day, value: 21, to: maxDate)!
        let span = calendar.dateComponents([.day], from: firstDay, to: last).day ?? 28
        let dayCount = ((span + 6) / 7) * 7

        return GanttLayout(
            calendar: calendar, firstDay: firstDay, dayCount: dayCount,
            dayWidth: dayWidth, today: today, rows: rows, unscheduled: unscheduled
        )
    }

    // MARK: - Geometría

    var totalWidth: CGFloat { CGFloat(dayCount) * dayWidth }

    /// Borde izquierdo del día que contiene `date` (negativo si cae antes del eje).
    func x(_ date: Date) -> CGFloat {
        CGFloat(calendar.dateComponents([.day], from: firstDay, to: date).day ?? 0) * dayWidth
    }

    /// Fecha del día `index` del eje.
    func day(_ index: Int) -> Date {
        calendar.date(byAdding: .day, value: index, to: firstDay)!
    }

    func adding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// Marco (x, ancho) de la figura de una fila, recortado al eje. Las barras
    /// incluyen el día final completo; el ancho mínimo es un día.
    func frame(for kind: Row.Kind) -> (x: CGFloat, width: CGFloat) {
        switch kind {
        case let .bar(start, end):
            let x0 = min(max(0, x(start)), totalWidth - dayWidth)
            let x1 = max(min(totalWidth, x(end) + dayWidth), x0 + dayWidth)
            return (x0, x1 - x0)
        case let .milestone(date):
            return (min(max(0, x(date)), totalWidth - dayWidth), dayWidth)
        case let .openEnded(start):
            let x0 = min(max(0, x(start)), totalWidth - dayWidth)
            let x1 = x(today) + dayWidth
            return (x0, max(dayWidth, x1 - x0))
        }
    }

    // MARK: - Ticks de cabecera

    /// Segmentos de mes visibles: (x, ancho, primer día del mes).
    var monthTicks: [(x: CGFloat, width: CGFloat, month: Date)] {
        var ticks: [(CGFloat, CGFloat, Date)] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: firstDay))!
        let end = day(dayCount)
        while cursor < end {
            let next = calendar.date(byAdding: .month, value: 1, to: cursor)!
            let x0 = max(0, x(cursor))
            let x1 = min(totalWidth, x(next))
            if x1 > x0 { ticks.append((x0, x1 - x0, cursor)) }
            cursor = next
        }
        return ticks
    }

    /// Lunes de cada semana del eje: (x, fecha).
    var weekTicks: [(x: CGFloat, monday: Date)] {
        stride(from: 0, to: dayCount, by: 7).map { (CGFloat($0) * dayWidth, day($0)) }
    }

    // MARK: - Fechas ISO

    static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        return f
    }

    static func parseDay(_ iso: String?, formatter: DateFormatter, calendar: Calendar) -> Date? {
        guard let iso, let date = formatter.date(from: iso) else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func isoString(_ date: Date, calendar: Calendar) -> String {
        dayFormatter(calendar: calendar).string(from: date)
    }

    /// Luminancia relativa (0 oscuro … 1 claro) de un color "#RRGGBB";
    /// decide si el texto sobre una barra va claro u oscuro.
    static func luminance(hex: String?) -> Double {
        guard let hex else { return 0 }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return 0 }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255
    }
}
