import SwiftUI

/// Ficha de detalle de un proyecto del portafolio: situación, agenda, tareas
/// por estado, entregado, reuniones y correos, y cronología de pasos. Ocupa el
/// panel derecho del maestro-detalle de `PortfolioBoard`.
struct PortfolioDetailView: View {
    @Environment(AppState.self) private var app
    let entry: PortfolioEntry
    /// Abre el tablero de la ficha en el modo dado ("kanban" | "gantt").
    let onOpenBoard: (String) -> Void
    /// Vuelve a la rejilla de tarjetas.
    let onClose: () -> Void

    /// Borrador de la situación mientras se edita a mano; nil = solo lectura.
    @State private var draft: Portfolio.Situation?

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var project: Project? { app.projects.first { $0.id == entry.plane.projectId } }

    var body: some View {
        let scope = app.portfolioScope(for: entry)
        let today = Portfolio.todayISO()
        // Responsive: el contenido se reparte en columnas según el ancho real
        // del panel, en vez de dejar media pantalla vacía en ventana grande.
        GeometryReader { geo in
            let columns = Self.columnCount(width: geo.size.width, fontScale: fs)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    situation
                        // Tope de lectura solo para el titular: es prosa.
                        .frame(maxWidth: 900 * fs, alignment: .leading)
                    switch columns {
                    case 3:
                        HStack(alignment: .top, spacing: 28) {
                            column { agendaBlock(scope, today: today); events }
                            column { workBlock(scope, today: today) }
                            column { steps }
                        }
                    case 2:
                        HStack(alignment: .top, spacing: 28) {
                            column { agendaBlock(scope, today: today); events; steps }
                            column { workBlock(scope, today: today) }
                        }
                    default:
                        column {
                            agendaBlock(scope, today: today)
                            workBlock(scope, today: today)
                            events
                            steps
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onClose)
    }

    /// Columnas del detalle para un ancho dado: una en el panel de la barra de
    /// menús, dos en ventana mediana, tres en pantalla completa.
    nonisolated static func columnCount(width: CGFloat, fontScale: CGFloat) -> Int {
        if width >= 1500 * fontScale { return 3 }
        if width >= 950 * fontScale { return 2 }
        return 1
    }

    private func column(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Hitos de la ficha y vencimientos de tareas.
    @ViewBuilder
    private func agendaBlock(_ scope: (items: [WorkItem], states: [WorkItemState])?, today: String) -> some View {
        if let scope {
            agenda(Portfolio.agenda(entry: entry, items: scope.items, states: scope.states, todayISO: today))
        }
    }

    /// Tareas por estado y lo entregado en la semana.
    @ViewBuilder
    private func workBlock(_ scope: (items: [WorkItem], states: [WorkItemState])?, today: String) -> some View {
        if let scope {
            startedItems(scope)
            delivered(Portfolio.delivered(
                items: scope.items, states: scope.states,
                sinceISO: Portfolio.dayISO(today, minusDays: Portfolio.deliveredDays)
            ))
        } else {
            Text("Tareas de Plane: sin cargar")
                .font(.system(size: 11 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 15 * fs, weight: .bold))
                Text([project?.name, entry.plane.module, Portfolio.statusLabel(entry.status)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10 * fs))
                    .foregroundStyle(app.theme.secondaryStyle)
            }
            Spacer()
            Button("Tareas") { onOpenBoard("kanban") }
            Button("Cronograma") { onOpenBoard("gantt") }
            Button {
                draft = draft == nil ? Portfolio.Situation(entry) : nil
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(draft == nil ? app.theme.primaryStyle : AnyShapeStyle(app.theme.accent ?? .accentColor))
            }
            .buttonStyle(.plain)
            .help("Editar la situación a mano")
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Volver a las tarjetas (Esc)")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var situation: some View {
        if draft != nil {
            situationEditor
        } else {
            situationText
        }
    }

    /// Edición a mano de titular, siguiente paso, espera y estado. Bloqueos e
    /// hitos siguen siendo cosa de `kodo portfolio set`.
    private var situationEditor: some View {
        let binding = Binding(get: { draft ?? Portfolio.Situation(entry) }, set: { draft = $0 })
        return VStack(alignment: .leading, spacing: 6) {
            editorField("Situación", text: binding.headline, lines: 2...4)
            editorField("Siguiente", text: binding.nextStep, lines: 1...3)
            editorField("Esperando a", text: binding.waitingOn, lines: 1...2)
            HStack(spacing: 8) {
                Picker("Estado", selection: binding.status) {
                    Text("Sin estado").tag("")
                    ForEach(Portfolio.statuses, id: \.self) { status in
                        Text(Portfolio.statusLabel(status) ?? status).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Button("Cancelar") { draft = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    if let draft { app.savePortfolioSituation(draft, for: entry) }
                    draft = nil
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .font(.system(size: 12 * fs))
    }

    private func editorField(_ label: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10 * fs, weight: .semibold))
                .foregroundStyle(app.theme.secondaryStyle)
                .frame(width: 78 * fs, alignment: .trailing)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(lines)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var situationText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.headline ?? "Sin situación registrada")
                .font(.system(size: 13 * fs))
                .foregroundStyle(entry.headline == nil ? app.theme.secondaryStyle : app.theme.primaryStyle)
                .textSelection(.enabled)
            if let next = entry.nextStep {
                labeled("Siguiente", next)
            }
            if let waiting = entry.waitingOn {
                labeled("Esperando a", waiting)
            }
            ForEach(entry.blockers, id: \.self) { blocker in
                labeled("Bloqueo", blocker, style: AnyShapeStyle(.red))
            }
        }
    }

    @ViewBuilder
    private func agenda(_ rows: [Portfolio.AgendaRow]) -> some View {
        if !rows.isEmpty {
            section("Fechas") {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shortDate(row.date))
                            .font(.system(size: 11 * fs, weight: .medium))
                            .frame(width: 52 * fs, alignment: .leading)
                        Image(systemName: row.itemID == nil ? "flag" : "checklist")
                            .font(.system(size: 9 * fs))
                            .help(row.itemID == nil ? "Hito" : "Vencimiento de tarea")
                        taskOrText(row.label, itemID: row.itemID)
                    }
                    .foregroundStyle(row.overdue ? AnyShapeStyle(.red) : app.theme.primaryStyle)
                }
            }
        }
    }

    /// Una sección por estado del grupo `started` con su nombre real de Plane
    /// (In Progress, In Review…): juntos confunden lo que se está haciendo con
    /// lo que ya espera revisión.
    private func startedItems(_ scope: (items: [WorkItem], states: [WorkItemState])) -> some View {
        ForEach(scope.states.filter { $0.group == "started" }) { state in
            stateSection(state, items: scope.items.filter { $0.state == state.id })
        }
    }

    @ViewBuilder
    private func delivered(_ items: [WorkItem]) -> some View {
        if !items.isEmpty {
            section("Entregado en los últimos \(Portfolio.deliveredDays) días (\(items.count))") {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shortDate(String((item.completedAt ?? "").prefix(10))))
                            .font(.system(size: 11 * fs, weight: .medium))
                            .frame(width: 52 * fs, alignment: .leading)
                        Text("\(project?.identifier ?? "")-\(item.sequenceId)")
                            .font(.system(size: 10 * fs, design: .monospaced))
                            .foregroundStyle(app.theme.secondaryStyle)
                        taskOrText(item.name, itemID: item.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stateSection(_ state: WorkItemState, items: [WorkItem]) -> some View {
        if !items.isEmpty {
            section("\(state.name) (\(items.count))") {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(project?.identifier ?? "")-\(item.sequenceId)")
                            .font(.system(size: 10 * fs, design: .monospaced))
                            .foregroundStyle(app.theme.secondaryStyle)
                        taskOrText(item.name, itemID: item.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var events: some View {
        if let events = entry.events, !events.isEmpty {
            section("Reuniones y correos") {
                ForEach(events, id: \.self) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shortDate(event.date))
                            .font(.system(size: 11 * fs, weight: .medium))
                            .frame(width: 52 * fs, alignment: .leading)
                        Image(systemName: event.kind == "email" ? "envelope" : "person.2")
                            .font(.system(size: 9 * fs))
                            .help(event.kind == "email" ? "Correo" : "Reunión")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 11 * fs, weight: .medium))
                            if let summary = event.summary {
                                Text(summary)
                                    .font(.system(size: 11 * fs))
                                    .foregroundStyle(app.theme.secondaryStyle)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var steps: some View {
        if !entry.steps.isEmpty {
            section("Últimos pasos") {
                ForEach(entry.steps, id: \.self) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shortDate(String(step.at.prefix(10))))
                            .font(.system(size: 11 * fs, weight: .medium))
                            .frame(width: 52 * fs, alignment: .leading)
                        Text(step.text + (step.source.map { "  (\($0))" } ?? ""))
                            .font(.system(size: 11 * fs))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        let days = Portfolio.ageInDays(updatedAt: entry.updatedAt, now: Date())
        Text("Ficha actualizada " + (days.map { $0 == 0 ? "hoy" : "hace \($0) días" } ?? "en fecha desconocida")
            + (entry.updatedBy.map { " · \($0)" } ?? ""))
            .font(.system(size: 9 * fs))
            .foregroundStyle((days ?? 0) > Portfolio.staleDays ? AnyShapeStyle(.orange) : app.theme.secondaryStyle)
    }

    // MARK: - Piezas

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(title.uppercased())
                .font(.system(size: 9 * fs, weight: .semibold))
                .foregroundStyle(app.theme.secondaryStyle)
            content()
        }
    }

    private func labeled(_ label: String, _ text: String, style: AnyShapeStyle? = nil) -> some View {
        (Text("\(label): ").fontWeight(.semibold) + Text(text))
            .font(.system(size: 11 * fs))
            .foregroundStyle(style ?? app.theme.primaryStyle)
            .textSelection(.enabled)
    }

    /// Nombre de tarea como enlace a Plane; texto plano si es un hito.
    @ViewBuilder
    private func taskOrText(_ text: String, itemID: String?) -> some View {
        if let itemID, let project,
           let item = app.itemsByProject[project.id]?.first(where: { $0.id == itemID }),
           let url = app.webURL(for: item, in: project) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text(text)
                    .font(.system(size: 11 * fs))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Abrir en Plane")
        } else {
            Text(text)
                .font(.system(size: 11 * fs))
                .lineLimit(2)
        }
    }

    /// "2026-11-20" → "20 nov".
    private func shortDate(_ iso: String) -> String {
        guard let date = GanttLayout.dayFormatter(calendar: .current).date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
