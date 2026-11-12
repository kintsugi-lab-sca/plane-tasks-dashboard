import SwiftUI

/// Ficha de detalle de un proyecto del portafolio (popover): situación,
/// agenda, tareas en curso y cronología completa de pasos.
struct PortfolioDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemColorScheme
    let entry: PortfolioEntry
    /// Abre el tablero de la ficha en el modo dado ("kanban" | "gantt").
    let onOpenBoard: (String) -> Void

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var project: Project? { app.projects.first { $0.id == entry.plane.projectId } }

    var body: some View {
        let scope = app.portfolioScope(for: entry)
        let today = GanttLayout.isoString(Date(), calendar: .current)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                situation
                if let scope {
                    agenda(Portfolio.agenda(entry: entry, items: scope.items, states: scope.states, todayISO: today))
                    inProgress(scope)
                } else {
                    Text("Tareas de Plane: sin cargar")
                        .font(.system(size: 11 * fs))
                        .foregroundStyle(app.theme.secondaryStyle)
                }
                events
                steps
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460 * fs)
        .frame(minHeight: 220, maxHeight: 600)
        // Mismo temado que WorkItemDetailView: el popover vive en su propia ventana.
        .foregroundStyle(app.theme.primaryStyle)
        .fontDesign(app.theme.monospaced ? .monospaced : .default)
        .environment(\.colorScheme, app.theme.colorScheme ?? systemColorScheme)
        .presentationBackground(app.theme.background ?? Color(nsColor: .windowBackgroundColor))
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
        }
        .controlSize(.small)
    }

    private var situation: some View {
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

    @ViewBuilder
    private func inProgress(_ scope: (items: [WorkItem], states: [WorkItemState])) -> some View {
        let started = Set(scope.states.filter { $0.group == "started" }.map(\.id))
        let items = scope.items.filter { started.contains($0.state) }
        if !items.isEmpty {
            section("En curso (\(items.count))") {
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
