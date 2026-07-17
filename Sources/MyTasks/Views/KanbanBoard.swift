import SwiftUI

struct KanbanBoard: View {
    @Environment(AppState.self) private var app
    /// true en la ventana redimensionable (ocupa todo el alto disponible);
    /// false en el panel de la barra de menú (alto fijo).
    var fillsHeight = false

    var body: some View {
        GeometryReader { geo in
            let fs = CGFloat(app.settings.fontScale)
            let count = max(1, app.kanbanStates.count)
            let fits = geo.size.width >= CGFloat(count) * 178 * fs + 20
            if fits {
                columns(flexible: true)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                ScrollView(.horizontal) {
                    columns(flexible: false)
                        .frame(height: geo.size.height)
                }
            }
        }
        .frame(height: fillsHeight ? nil : panelBoardHeight)
        .frame(maxHeight: fillsHeight ? .infinity : panelBoardHeight)
    }

    /// Alto del tablero en el panel: la mitad del alto visible de la pantalla
    /// (≈ un cuadrante junto con el ancho al 50 %), con el mínimo histórico
    /// de 448 pt para pantallas pequeñas.
    private var panelBoardHeight: CGFloat {
        max(448, (NSScreen.main?.visibleFrame.height ?? 900) * 0.5)
    }

    private func columns(flexible: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(app.kanbanStates) { state in
                KanbanColumn(state: state, flexible: flexible)
            }
        }
        .padding(10)
    }
}

struct KanbanColumn: View {
    @Environment(AppState.self) private var app
    let state: WorkItemState
    /// true → la columna se reparte el ancho disponible; false → ancho fijo (con scroll lateral).
    var flexible = false

    private var items: [WorkItem] { app.kanbanItems(in: state) }
    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: state.color) ?? .gray)
                    .frame(width: 8 * fs, height: 8 * fs)
                Text(state.name)
                    .font(.system(size: 11 * fs, weight: .bold))
                Text("\(items.count)")
                    .font(.system(size: 9 * fs))
                    .foregroundStyle(app.theme.secondaryStyle)
                Spacer()
            }
            .padding(.horizontal, 6)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if items.isEmpty {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)
                    }
                    ForEach(items) { item in
                        WorkItemCard(item: item)
                    }
                }
                .padding(2)
            }
        }
        .padding(6)
        .frame(minWidth: (flexible ? 160 : 210) * fs, maxWidth: flexible ? .infinity : 210 * fs)
        .background(app.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let item = app.workItem(id: id), item.state != state.id else {
                return false
            }
            Task { await app.changeState(of: item, to: state) }
            return true
        }
    }
}

struct WorkItemCard: View {
    @Environment(AppState.self) private var app
    let item: WorkItem

    @State private var hovering = false
    @State private var showDetail = false

    private var project: Project? { app.selectedProject }
    /// Todos los estados (con Done/Cancelled): desde aquí se cierran tareas.
    private var states: [WorkItemState] { app.allStates }
    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(project?.identifier ?? "")-\(item.sequenceId)")
                    .font(.system(size: 9 * fs, design: .monospaced))
                    .foregroundStyle(app.theme.secondaryStyle)
                Spacer()
                if item.priority == "urgent" || item.priority == "high" {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9 * fs))
                        .foregroundStyle(item.priority == "urgent" ? .red : .orange)
                        .help("Prioridad: \(item.priority)")
                }
                Button {
                    openInPlane()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10 * fs))
                        .foregroundStyle(hovering ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .help("Abrir en Plane")
            }
            Text(item.name)
                .font(.system(size: 12 * fs))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            metaRow
            stateTag
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        .background(app.theme.cardStyle, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(app.theme.cardBorderStyle))
        .onHover { hovering = $0 }
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            WorkItemDetailView(item: item)
        }
        .draggable(item.id)
        .contextMenu {
            // Contenido compartido con el gantt (ver WorkItemMenuContent).
            WorkItemMenuContent(item: item)
        }
    }

    /// Módulo, fechas y etiquetas — solo se renderiza si hay algo que mostrar.
    @ViewBuilder
    private var metaRow: some View {
        let module: Module? = app.module(for: item)
        let labels: [WorkItemLabel] = app.labels(for: item)
        if module != nil || item.targetDate != nil || item.startDate != nil || !labels.isEmpty {
            HStack(spacing: 6) {
                if let module {
                    chip(icon: "square.grid.2x2", text: module.name)
                        .help("Módulo: \(module.name)")
                }
                if let dates = dateText {
                    dateChip(dates)
                }
                ForEach(labels.prefix(2)) { label in
                    labelChip(label)
                }
                if labels.count > 2 {
                    Text("+\(labels.count - 2)")
                        .font(.system(size: 9 * fs))
                        .foregroundStyle(app.theme.secondaryStyle)
                        .help(labels.map(\.name).joined(separator: ", "))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func chip(icon: String, text: String, style: AnyShapeStyle? = nil) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8 * fs))
            Text(text)
                .font(.system(size: 9 * fs))
                .lineLimit(1)
        }
        .foregroundStyle(style ?? app.theme.secondaryStyle)
    }

    private func dateChip(_ text: String) -> some View {
        chip(icon: "calendar", text: text, style: isOverdue ? AnyShapeStyle(.red) : nil)
            .help(isOverdue ? "Vencida" : "Fechas")
    }

    private func labelChip(_ label: WorkItemLabel) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: label.color) ?? .gray)
                .frame(width: 6 * fs, height: 6 * fs)
            Text(label.name)
                .font(.system(size: 9 * fs))
                .lineLimit(1)
        }
        .foregroundStyle(app.theme.secondaryStyle)
    }

    /// "13–14 abr", "→ 14 abr" (solo fecha límite) o "13 abr →" (solo inicio).
    private var dateText: String? {
        let start = Self.shortDate(item.startDate)
        let target = Self.shortDate(item.targetDate)
        switch (start, target) {
        case (nil, nil): return nil
        case let (s?, nil): return "\(s) →"
        case let (nil, t?): return "→ \(t)"
        case let (s?, t?): return s == t ? s : "\(s)–\(t)"
        }
    }

    private var isOverdue: Bool {
        guard let target = item.targetDate else { return false }
        return target < Self.todayISO
    }

    private static let todayISO: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }()

    private static func shortDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: iso) else { return nil }
        let output = DateFormatter()
        output.setLocalizedDateFormatFromTemplate("d MMM")
        return output.string(from: date)
    }

    /// Tag del estado actual: clicable para mover la tarea a otro estado.
    /// NSMenu de AppKit construido al pulsar: un Menu de SwiftUI inline por
    /// card (AppKitPopUpAdaptor) mete al view graph en un bucle infinito de
    /// invalidación en macOS 26 — freeze con CPU al 100% al reordenar/scrollear.
    private var stateTag: some View {
        Button {
            popUpStateMenu()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: app.state(of: item)?.color) ?? .gray)
                    .frame(width: 7 * fs, height: 7 * fs)
                Text(app.state(of: item)?.name ?? "Estado")
                    .font(.system(size: 9 * fs))
                    .foregroundStyle(app.theme.secondaryStyle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7 * fs))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Cambiar estado")
    }

    private func popUpStateMenu() {
        let menu = NSMenu()
        for state in states {
            let app = self.app
            let item = self.item
            menu.addItem(ClosureMenuItem(title: state.name, checked: state.id == item.state) {
                Task { await app.changeState(of: item, to: state) }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func openInPlane() {
        guard let project, let url = app.webURL(for: item, in: project) else { return }
        NSWorkspace.shared.open(url)
    }
}

extension Color {
    /// Crea un color desde "#RRGGBB"; nil si el formato no es válido.
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
