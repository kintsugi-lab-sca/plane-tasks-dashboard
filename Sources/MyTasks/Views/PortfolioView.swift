import SwiftUI

/// Vista de portafolio: una tarjeta por proyecto en marcha. La narrativa viene
/// de la ficha que escribe kodo; los contadores y vencimientos, de Plane.
///
/// Dos disposiciones: rejilla de tarjetas, o —con una ficha seleccionada—
/// maestro-detalle: las tarjetas pasan a una columna de miniaturas a la
/// izquierda y el detalle ocupa el resto. `matchedGeometryEffect` hace que
/// cada tarjeta viaje hasta su miniatura en vez de aparecer de golpe.
struct PortfolioBoard: View {
    @Environment(AppState.self) private var app
    /// true en la ventana redimensionable; false en el panel (alto fijo).
    var fillsHeight = false

    @State private var showArchived = false
    @State private var selectedSlug: String?
    @Namespace private var cardSpace

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    /// Ficha abierta en el detalle; nil si no hay selección o la ficha ya no existe.
    private var selected: PortfolioEntry? {
        app.portfolio.first { $0.slug == selectedSlug }
    }

    private func select(_ slug: String?) {
        withAnimation(.snappy(duration: 0.32)) { selectedSlug = slug }
    }

    /// Activas, primero las que piden atención (bloqueo > vencidas > ficha
    /// antigua o sin situación) y dentro de cada nivel por nombre.
    private var active: [PortfolioEntry] {
        let now = Date()
        let ranked: [(entry: PortfolioEntry, level: Portfolio.Attention)] = app.portfolio
            .filter { !$0.archived }
            .map { entry in
                (entry, Portfolio.attention(entry: entry, stats: app.portfolioStats(for: entry), now: now))
            }
        return ranked
            .sorted { a, b in
                if a.level != b.level { return a.level > b.level }
                return a.entry.name.localizedCaseInsensitiveCompare(b.entry.name) == .orderedAscending
            }
            .map(\.entry)
    }
    private var archived: [PortfolioEntry] { app.portfolio.filter(\.archived) }

    var body: some View {
        Group {
            if let selected {
                HStack(spacing: 0) {
                    sidebar(selected: selected)
                    Divider()
                    PortfolioDetailView(
                        entry: selected,
                        onOpenBoard: { mode in
                            withAnimation(.snappy(duration: 0.25)) { app.openPortfolio(selected, mode: mode) }
                        },
                        onClose: { select(nil) }
                    )
                    .id(selected.slug)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            } else if app.portfolioShowsAgenda {
                PortfolioAgendaView { slug in
                    app.portfolioShowsAgenda = false
                    select(slug)
                }
                .transition(.opacity)
            } else {
                cardGrid
            }
        }
        .frame(height: fillsHeight ? nil : panelBoardHeight)
        .frame(maxHeight: fillsHeight ? .infinity : panelBoardHeight)
    }

    /// Columna de miniaturas del maestro-detalle (mismo orden que la rejilla).
    private func sidebar(selected: PortfolioEntry) -> some View {
        VStack(spacing: 0) {
            // Volver a la rejilla, fijo sobre la lista para que no se pierda al
            // hacer scroll.
            Button {
                select(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    Text("Todas las tarjetas")
                    Spacer()
                }
                .font(.system(size: 11 * fs, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.theme.accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
            .help("Volver a la vista de tarjetas (Esc)")
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(active + (selected.archived ? [selected] : [])) { entry in
                        PortfolioMiniCard(entry: entry, isSelected: entry.slug == selected.slug)
                            .matchedGeometryEffect(id: entry.slug, in: cardSpace)
                            .onTapGesture { select(entry.slug == selected.slug ? nil : entry.slug) }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 230 * fs)
    }

    private var cardGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if app.portfolio.isEmpty {
                    emptyHint
                }
                grid(active)
                if !archived.isEmpty {
                    Button {
                        showArchived.toggle()
                    } label: {
                        Label(
                            "Archivados (\(archived.count))",
                            systemImage: showArchived ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 11 * fs))
                        .foregroundStyle(app.theme.secondaryStyle)
                    }
                    .buttonStyle(.plain)
                    if showArchived {
                        grid(archived)
                            .opacity(0.6)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Mismo alto que el kanban en el panel.
    private var panelBoardHeight: CGFloat {
        max(448, (NSScreen.main?.visibleFrame.height ?? 900) * 0.5)
    }

    private func grid(_ entries: [PortfolioEntry]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260 * fs), spacing: 8, alignment: .top)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(entries) { entry in
                PortfolioCard(entry: entry) { select(entry.slug) }
                    .matchedGeometryEffect(id: entry.slug, in: cardSpace)
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("El portafolio está vacío.")
                .font(.system(size: 12 * fs, weight: .semibold))
            Text("Las fichas las crea el orquestador con:")
                .foregroundStyle(app.theme.secondaryStyle)
            Text("kodo portfolio set <slug> --name … --plane-project …")
                .font(.system(size: 11 * fs, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.system(size: 11 * fs))
        .padding(14)
    }
}

struct PortfolioCard: View {
    @Environment(AppState.self) private var app
    let entry: PortfolioEntry
    /// Abre la ficha en el detalle.
    let onSelect: () -> Void

    @State private var hovering = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        let stats = app.portfolioStats(for: entry)
        let today = GanttLayout.isoString(Date(), calendar: .current)
        VStack(alignment: .leading, spacing: 6) {
            // Una ficha de módulo lleva encima el proyecto de Plane: hay
            // módulos con el mismo nombre en proyectos distintos («DEV»).
            if entry.plane.module != nil,
               let project = app.projects.first(where: { $0.id == entry.plane.projectId }) {
                Text(project.name.uppercased())
                    .font(.system(size: 9 * fs, weight: .semibold))
                    .foregroundStyle(app.theme.secondaryStyle)
                    .lineLimit(1)
                    .padding(.bottom, -3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.name)
                    .font(.system(size: 13 * fs, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                statusPill
            }
            Text(entry.headline ?? "Sin situación registrada")
                .font(.system(size: 12 * fs))
                .foregroundStyle(entry.headline == nil ? app.theme.secondaryStyle : app.theme.primaryStyle)
                .lineLimit(3)
            if let next = entry.nextStep {
                line(icon: "arrow.right.circle", text: "Siguiente: \(next)")
            }
            if let waiting = entry.waitingOn {
                line(icon: "hourglass", text: "Esperando a: \(waiting)")
            }
            if let blocker = entry.blockers.first {
                let extra = entry.blockers.count > 1 ? " (+\(entry.blockers.count - 1))" : ""
                line(icon: "exclamationmark.octagon.fill", text: "Bloqueo: \(blocker)\(extra)", style: AnyShapeStyle(.red))
            }
            if let upcoming = Portfolio.upcoming(entry: entry, stats: stats, todayISO: today) {
                line(icon: "calendar", text: "\(shortDate(upcoming.date)) · \(upcoming.label)")
            }
            if let event = entry.events?.first {
                line(
                    icon: event.kind == "email" ? "envelope" : "person.2",
                    text: "\(shortDate(event.date)) · \(event.title)"
                )
            }
            if !entry.steps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.steps.prefix(2), id: \.self) { step in
                        Text("\(shortDate(String(step.at.prefix(10)))) — \(step.text)")
                            .lineLimit(2)
                    }
                }
                .font(.system(size: 10 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            progress(stats)
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 150 * fs, alignment: .topLeading)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
        .background(app.theme.cardStyle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(app.theme.cardBorderStyle))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Ver tareas") { open("kanban") }
            Button("Ver cronograma") { open("gantt") }
            Divider()
            Button(entry.archived ? "Recuperar" : "Archivar") {
                app.setPortfolioArchived(entry, archived: !entry.archived)
            }
        }
    }

    private func open(_ mode: String) {
        withAnimation(.snappy(duration: 0.25)) { app.openPortfolio(entry, mode: mode) }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let label = Portfolio.statusLabel(entry.status) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7 * fs, height: 7 * fs)
                Text(label)
                    .font(.system(size: 10 * fs, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.14), in: Capsule())
        }
    }

    private var statusColor: Color { entry.statusColor }

    private func line(icon: String, text: String, style: AnyShapeStyle? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9 * fs))
                .frame(width: 11 * fs)
            Text(text)
                .lineLimit(2)
        }
        .font(.system(size: 11 * fs))
        .foregroundStyle(style ?? app.theme.primaryStyle)
    }

    /// Barra de avance y contadores de Plane; mientras no hay datos, un guion.
    @ViewBuilder
    private func progress(_ stats: Portfolio.Stats?) -> some View {
        if let stats {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: Double(stats.done), total: Double(max(stats.total, 1)))
                    .controlSize(.small)
                // Con nombres de estado si caben; si no, solo punto de color + número.
                ViewThatFits(in: .horizontal) {
                    counters(stats, named: true)
                    counters(stats, named: false)
                }
                .font(.system(size: 10 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
            }
        } else {
            Text(entry.plane.module != nil && app.modulesByProject[entry.plane.projectId] != nil
                && app.portfolioModule(for: entry) == nil
                ? "Módulo «\(entry.plane.module ?? "")» no encontrado en Plane"
                : "Tareas: cargando…")
                .font(.system(size: 10 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
        }
    }

    /// Hechas · un contador por estado `started` con su nombre y color reales
    /// de Plane (In Progress, In Review…) · por hacer · vencidas.
    private func counters(_ stats: Portfolio.Stats, named: Bool) -> some View {
        HStack(spacing: 10) {
            counter("checkmark.circle", stats.done, "Hechas")
            if stats.deliveredRecently > 0 {
                // Entre paréntesis: «2 +1» a secas se leía como una suma.
                Text(named ? "(\(stats.deliveredRecently) esta semana)" : "(+\(stats.deliveredRecently))")
                    .fixedSize()
                    .padding(.leading, -7)
                    .help("Entregadas en los últimos \(Portfolio.deliveredDays) días")
            }
            ForEach((app.statesByProject[entry.plane.projectId] ?? []).filter { $0.group == "started" }) { state in
                if let count = stats.started[state.id] {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: state.color) ?? .gray)
                            .frame(width: 6 * fs, height: 6 * fs)
                        Text(named ? "\(count) \(state.name)" : "\(count)")
                    }
                    .fixedSize()
                    .help(state.name)
                }
            }
            counter("circle", stats.todo, "Por hacer")
            if stats.overdue > 0 {
                counter("exclamationmark.triangle.fill", stats.overdue, "Vencidas")
                    .foregroundStyle(.red)
            }
        }
    }

    /// Contador compacto (icono + número): con texto no caben los cuatro en
    /// el ancho mínimo de la tarjeta. El significado va en el tooltip.
    private func counter(_ icon: String, _ value: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text("\(value)")
        }
        .fixedSize()
        .help(label)
    }

    /// Antigüedad de la narrativa: un resumen viejo debe notarse.
    private var footer: some View {
        let days = Portfolio.ageInDays(updatedAt: entry.updatedAt, now: Date())
        let unreported = app.portfolioStats(for: entry)?.unreported ?? 0
        let stale = (days ?? 0) > Portfolio.staleDays || unreported > 0
        let age = switch days {
        case nil: "fecha desconocida"
        case 0: "hoy"
        case 1: "ayer"
        case let d?: "hace \(d) días"
        }
        return HStack(spacing: 4) {
            if stale {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            Text(unreported > 0
                ? "Actualizado \(age) · \(unreported) \(unreported == 1 ? "entrega" : "entregas") sin reflejar"
                : "Actualizado \(age)" + (entry.updatedBy.map { " · \($0)" } ?? ""))
                .lineLimit(1)
        }
        .help(unreported > 0 ? "Hay tareas completadas en Plane después de la última actualización de la ficha" : "")
        .font(.system(size: 9 * fs))
        .foregroundStyle(stale ? AnyShapeStyle(.orange) : app.theme.secondaryStyle)
    }

    /// "2026-11-20" → "20 nov".
    private func shortDate(_ iso: String) -> String {
        guard let date = GanttLayout.dayFormatter(calendar: .current).date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

extension PortfolioEntry {
    /// Color del semáforo (vocabulario de kodo).
    var statusColor: Color {
        switch status {
        case "on_track": .green
        case "at_risk": .orange
        case "blocked": .red
        case "waiting": .blue
        default: .gray
        }
    }
}

/// Tarjeta en miniatura para la columna del maestro-detalle: proyecto, nombre,
/// semáforo, aviso de atención y titular en una línea.
struct PortfolioMiniCard: View {
    @Environment(AppState.self) private var app
    let entry: PortfolioEntry
    let isSelected: Bool

    @State private var hovering = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        let attention = Portfolio.attention(entry: entry, stats: app.portfolioStats(for: entry), now: Date())
        VStack(alignment: .leading, spacing: 2) {
            if entry.plane.module != nil,
               let project = app.projects.first(where: { $0.id == entry.plane.projectId }) {
                Text(project.name.uppercased())
                    .font(.system(size: 8 * fs, weight: .semibold))
                    .foregroundStyle(app.theme.secondaryStyle)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                if entry.status != nil {
                    Circle()
                        .fill(entry.statusColor)
                        .frame(width: 6 * fs, height: 6 * fs)
                        .help(Portfolio.statusLabel(entry.status) ?? "")
                }
                Text(entry.name)
                    .font(.system(size: 11 * fs, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                switch attention {
                case .blocked:
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red).help("Bloqueado")
                case .overdue:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help("Tareas vencidas o en riesgo")
                case .stale:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Ficha atrasada o sin situación")
                case .none:
                    EmptyView()
                }
            }
            .font(.system(size: 9 * fs))
            Text(entry.headline ?? "Sin situación registrada")
                .font(.system(size: 9 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(hovering || isSelected ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
        .background(app.theme.cardStyle, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? AnyShapeStyle(app.theme.accent ?? .accentColor) : app.theme.cardBorderStyle,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}

/// Agenda conjunta del portafolio, con forma de calendario: una fila por día
/// de los próximos 14 (también los vacíos, para que se lea como una semana y no
/// como una lista), la fecha grande a la izquierda y a la derecha lo que cae
/// ese día. Los hitos van primero y destacados; las tareas, debajo. Lo vencido
/// se recoge en una barra plegada para que la agenda abra en HOY.
struct PortfolioAgendaView: View {
    @Environment(AppState.self) private var app
    /// Abre la ficha de un proyecto.
    let onSelect: (String) -> Void

    @State private var showOverdue = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var accent: AnyShapeStyle { AnyShapeStyle(app.theme.accent ?? .accentColor) }

    var body: some View {
        let groups = app.portfolioWeekAgenda
        let today = Portfolio.todayISO()
        let byDay = Dictionary(uniqueKeysWithValues: groups.compactMap { day in day.date.map { ($0, day.rows) } })
        let overdue = groups.first { $0.date == nil }?.rows ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !overdue.isEmpty {
                    overdueBar(overdue)
                }
                ForEach(0...Portfolio.agendaDays, id: \.self) { offset in
                    let date = Portfolio.dayISO(today, minusDays: -offset)
                    dayRow(date: date, offset: offset, rows: byDay[date] ?? [])
                    Divider().opacity(0.5)
                }
            }
            .padding(14)
            .frame(maxWidth: 1000 * fs, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Barra plegable con las tareas vencidas (cada una con su fecha).
    private func overdueBar(_ rows: [Portfolio.WeekRow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showOverdue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(rows.count) \(rows.count == 1 ? "vencida" : "vencidas")")
                        .fontWeight(.semibold)
                    Image(systemName: showOverdue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9 * fs))
                    Spacer()
                }
                .font(.system(size: 11 * fs))
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showOverdue {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortDate(row.row.date))
                            .font(.system(size: 11 * fs, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 52 * fs, alignment: .leading)
                        item(row)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 10)
    }

    /// Un día: fecha a la izquierda, lo que cae ese día a la derecha.
    private func dayRow(date: String, offset: Int, rows: [Portfolio.WeekRow]) -> some View {
        let parsed = GanttLayout.dayFormatter(calendar: .current).date(from: date)
        let weekend = parsed.map { Calendar.current.isDateInWeekend($0) } ?? false
        let isToday = offset == 0
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(isToday ? "HOY" : offset == 1 ? "MAÑANA"
                    : (parsed?.formatted(.dateTime.weekday(.abbreviated)) ?? "").uppercased())
                    .font(.system(size: 9 * fs, weight: .semibold))
                Text(parsed?.formatted(.dateTime.day().month(.abbreviated)) ?? date)
                    .font(.system(size: 14 * fs, weight: .bold))
            }
            .foregroundStyle(isToday ? accent : rows.isEmpty ? AnyShapeStyle(.tertiary) : app.theme.primaryStyle)
            .frame(width: 78 * fs, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                if rows.isEmpty {
                    Text("—")
                        .font(.system(size: 11 * fs))
                        .foregroundStyle(.tertiary)
                }
                ForEach(rows) { row in
                    item(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
        }
        .padding(.vertical, rows.isEmpty ? 4 : 8)
        .opacity(weekend && rows.isEmpty ? 0.5 : 1)
    }

    /// Hito (bandera, destacado) o vencimiento de tarea, con su proyecto.
    private func item(_ row: Portfolio.WeekRow) -> some View {
        let isMilestone = row.row.itemID == nil
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isMilestone {
                MilestoneToggle(done: row.row.done, size: 11 * fs) {
                    app.setPortfolioMilestone(
                        slug: row.slug, date: row.row.date, label: row.row.label, done: !row.row.done
                    )
                }
                .foregroundStyle(row.row.overdue ? AnyShapeStyle(.red) : accent)
                .frame(width: 12 * fs)
            } else {
                StateDot(color: row.row.stateColor, name: row.row.stateName, size: 7 * fs)
                    .frame(width: 12 * fs)
            }
            Button {
                onSelect(row.slug)
            } label: {
                Text(row.entryName)
                    .font(.system(size: 10 * fs, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Abrir la ficha")
            Text(row.row.label)
                .font(.system(size: (isMilestone ? 12 : 11) * fs, weight: isMilestone ? .semibold : .regular))
                .strikethrough(row.row.done)
                .foregroundStyle(row.row.overdue ? AnyShapeStyle(.red)
                    : isMilestone && !row.row.done ? app.theme.primaryStyle : app.theme.secondaryStyle)
                .lineLimit(2)
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let date = GanttLayout.dayFormatter(calendar: .current).date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
