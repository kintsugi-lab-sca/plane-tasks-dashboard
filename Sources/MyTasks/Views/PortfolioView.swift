import SwiftUI

/// Vista de portafolio: una tarjeta por proyecto en marcha. La narrativa viene
/// de la ficha que escribe kodo; los contadores y vencimientos, de Plane.
struct PortfolioBoard: View {
    @Environment(AppState.self) private var app
    /// true en la ventana redimensionable; false en el panel (alto fijo).
    var fillsHeight = false

    @State private var showArchived = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var active: [PortfolioEntry] { app.portfolio.filter { !$0.archived } }
    private var archived: [PortfolioEntry] { app.portfolio.filter(\.archived) }

    var body: some View {
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
        .frame(height: fillsHeight ? nil : panelBoardHeight)
        .frame(maxHeight: fillsHeight ? .infinity : panelBoardHeight)
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
                PortfolioCard(entry: entry)
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

    @State private var hovering = false
    @State private var showDetail = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        let stats = app.portfolioStats(for: entry)
        let today = GanttLayout.isoString(Date(), calendar: .current)
        VStack(alignment: .leading, spacing: 6) {
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
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            PortfolioDetailView(entry: entry) { mode in
                showDetail = false
                open(mode)
            }
        }
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

    private var statusColor: Color {
        switch entry.status {
        case "on_track": .green
        case "at_risk": .orange
        case "blocked": .red
        case "waiting": .blue
        default: .gray
        }
    }

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
                HStack(spacing: 10) {
                    counter("checkmark.circle", stats.done, "Hechas")
                    counter("play.circle", stats.inProgress, "En curso")
                    if stats.inReview > 0 {
                        counter("eye", stats.inReview, "En revisión")
                    }
                    counter("circle", stats.todo, "Por hacer")
                    if stats.overdue > 0 {
                        counter("exclamationmark.triangle.fill", stats.overdue, "Vencidas")
                            .foregroundStyle(.red)
                    }
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
        let stale = (days ?? 0) > Portfolio.staleDays
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
            Text("Actualizado \(age)" + (entry.updatedBy.map { " · \($0)" } ?? ""))
                .lineLimit(1)
        }
        .font(.system(size: 9 * fs))
        .foregroundStyle(stale ? AnyShapeStyle(.orange) : app.theme.secondaryStyle)
    }

    /// "2026-11-20" → "20 nov".
    private func shortDate(_ iso: String) -> String {
        guard let date = GanttLayout.dayFormatter(calendar: .current).date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
