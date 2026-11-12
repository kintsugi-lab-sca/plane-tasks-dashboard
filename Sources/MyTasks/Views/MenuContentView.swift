import SwiftUI

struct MenuContentView: View {
    /// true cuando se muestra en la ventana independiente (redimensionable);
    /// false en el panel anclado a la barra de menú.
    var isWindow = false

    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var showQuickAdd = false
    @State private var quickAddText = ""
    @State private var quickAddPriority = "none"
    @State private var quickAddLabelIDs: Set<String> = []
    @State private var isCreating = false
    @FocusState private var quickAddFocused: Bool
    @Namespace private var viewToggleNS

    var body: some View {
        VStack(spacing: 0) {
            header
            if showQuickAdd, !isPortfolio {
                quickAddRow
            }
            Divider()
            content
        }
        .frame(width: isWindow ? nil : panelWidth)
        .frame(minWidth: isWindow ? 640 : nil, minHeight: isWindow ? 420 : nil)
        .foregroundStyle(app.theme.primaryStyle)
        .background(app.theme.background ?? .clear)
        .tint(app.theme.accent)
        .fontDesign(app.theme.monospaced ? .monospaced : .default)
        .environment(\.colorScheme, app.theme.colorScheme ?? systemColorScheme)
        .task {
            await app.refresh()
            await app.loadModules()
        }
    }

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    /// Ancho del panel: que quepan todas las columnas sin scroll lateral y,
    /// con tablero visible, al menos media pantalla (≈ un cuadrante junto con
    /// el alto al 50 %). Tope al 85 % de la pantalla. En modo gantt el ancho
    /// no depende de columnas: panel generoso para el eje temporal.
    private var panelWidth: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        if app.settings.boardMode == "gantt" {
            return screenWidth * 0.62
        }
        if isPortfolio {
            return screenWidth * 0.5
        }
        let count = max(2, app.kanbanStates.count)
        let ideal = CGFloat(count) * 216 * fs + 28
        let minWidth = app.kanbanStates.isEmpty ? 0 : screenWidth * 0.5
        return min(max(ideal, minWidth), screenWidth * 0.85)
    }

    /// En la vista de portafolio la cabecera no muestra pickers ni filtros:
    /// son del tablero de tareas.
    private var isPortfolio: Bool { app.settings.boardMode == "portfolio" }

    private var header: some View {
        HStack(spacing: 10) {
            if isPortfolio {
                Text("Portafolio")
                    .font(.system(size: 13 * fs, weight: .semibold))
            } else {
                projectPicker
                modulePicker
                cyclePicker
            }
            if app.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            viewToggle
            if !isPortfolio {
                searchField
                priorityFilterButton
                Button {
                    showQuickAdd.toggle()
                    if showQuickAdd { quickAddFocused = true }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(showQuickAdd ? AnyShapeStyle(app.theme.accent ?? .accentColor) : app.theme.primaryStyle)
                }
                .help("Crear tarea rápida")
                Button {
                    app.settings.onlyMine.toggle()
                } label: {
                    Image(systemName: app.settings.onlyMine ? "person.fill" : "person.2.fill")
                        .foregroundStyle(app.settings.onlyMine ? AnyShapeStyle(app.theme.accent ?? .accentColor) : app.theme.primaryStyle)
                }
                .help(app.settings.onlyMine ? "Mostrando solo mis tareas — clic para ver todas" : "Mostrando todas — clic para ver solo las mías")
            }
            Button {
                Task { await app.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Actualizar")
            if !isWindow {
                Button {
                    AppWindows.shared.showBoard()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("Abrir en ventana")
            }
            Button {
                AppWindows.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Ajustes")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Salir")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12 * fs))
        .padding(.leading, isWindow ? 78 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
    }

    /// Conmutador kanban ↔ gantt: cápsula con indicador deslizante.
    private var viewToggle: some View {
        HStack(spacing: 2) {
            viewToggleSegment(icon: "rectangle.grid.2x2", mode: "portfolio", help: "Portafolio de proyectos")
            viewToggleSegment(icon: "square.grid.3x1.below.line.grid.1x2", mode: "kanban", help: "Tablero kanban")
            viewToggleSegment(icon: GanttSymbols.gantt, mode: "gantt", help: "Cronograma (gantt)")
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func viewToggleSegment(icon: String, mode: String, help: String) -> some View {
        let active = app.settings.boardMode == mode
        return Button {
            withAnimation(.snappy(duration: 0.25)) { app.settings.boardMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10 * fs, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(app.theme.accent ?? .accentColor) : app.theme.secondaryStyle)
                .frame(width: 26 * fs, height: 18 * fs)
                .background {
                    if active {
                        Capsule()
                            .fill(app.theme.cardStyle)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "board-view", in: viewToggleNS)
                    }
                }
                .contentShape(Capsule())
        }
        .help(help)
    }

    /// Filtro por prioridad: NSMenu on-demand (mismo gotcha que el resto de
    /// menús: Menu de SwiftUI inline congela macOS 26).
    private var priorityFilterButton: some View {
        Button {
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem(title: "Todas las prioridades", checked: app.priorityFilter == nil) {
                app.priorityFilter = nil
            })
            menu.addItem(.separator())
            for (value, name) in WorkItemPriority.options {
                menu.addItem(ClosureMenuItem(title: name, checked: app.priorityFilter == value) {
                    app.priorityFilter = value
                })
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            Image(systemName: app.priorityFilter == nil ? "flag" : "flag.fill")
                .foregroundStyle(priorityFilterStyle)
        }
        .help(app.priorityFilter == nil
            ? "Filtrar por prioridad"
            : "Filtrando por prioridad — clic para cambiar")
    }

    private var priorityFilterStyle: AnyShapeStyle {
        switch app.priorityFilter {
        case "urgent": AnyShapeStyle(.red)
        case "high": AnyShapeStyle(.orange)
        case nil: app.theme.primaryStyle
        default: AnyShapeStyle(app.theme.accent ?? .accentColor)
        }
    }

    /// Búsqueda client-side sobre las tareas cargadas; Esc limpia el campo.
    private var searchField: some View {
        @Bindable var app = app
        return HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
            TextField("Buscar", text: $app.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11 * fs))
                .onExitCommand { app.searchText = "" }
            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10 * fs))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 150)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    /// Fila de creación rápida: Enter crea la tarea en el proyecto (y módulo)
    /// seleccionado; Esc la cierra. Los botones de prioridad y etiquetas usan
    /// NSMenu on-demand (ver gotcha: Menu de SwiftUI inline congela macOS 26).
    private var quickAddRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .foregroundStyle(app.theme.secondaryStyle)
            TextField(
                "Nueva tarea en \(app.selectedProject?.name ?? "el proyecto")…",
                text: $quickAddText
            )
            .textFieldStyle(.plain)
            .focused($quickAddFocused)
            .onSubmit { submitQuickAdd() }
            .onExitCommand { resetQuickAdd() }
            quickAddPriorityButton
            if !quickAddProjectLabels.isEmpty {
                quickAddLabelsButton
            }
            if isCreating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.system(size: 12 * fs))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: app.selectedProjectID) {
            quickAddLabelIDs = []
        }
    }

    private var quickAddProjectLabels: [WorkItemLabel] {
        guard let project = app.selectedProject else { return [] }
        return app.labelsByProject[project.id] ?? []
    }

    private var quickAddPriorityButton: some View {
        Button {
            let menu = NSMenu()
            for (value, name) in WorkItemPriority.options {
                menu.addItem(ClosureMenuItem(title: name, checked: value == quickAddPriority) {
                    quickAddPriority = value
                })
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            Image(systemName: quickAddPriority == "none" ? "flag" : "flag.fill")
                .foregroundStyle(quickAddPriorityStyle)
        }
        .buttonStyle(.plain)
        .help("Prioridad de la nueva tarea")
    }

    private var quickAddPriorityStyle: AnyShapeStyle {
        switch quickAddPriority {
        case "urgent": AnyShapeStyle(.red)
        case "high": AnyShapeStyle(.orange)
        case "none": app.theme.secondaryStyle
        default: AnyShapeStyle(app.theme.accent ?? .accentColor)
        }
    }

    private var quickAddLabelsButton: some View {
        Button {
            let menu = NSMenu()
            for label in quickAddProjectLabels {
                menu.addItem(ClosureMenuItem(title: label.name, checked: quickAddLabelIDs.contains(label.id)) {
                    if quickAddLabelIDs.contains(label.id) {
                        quickAddLabelIDs.remove(label.id)
                    } else {
                        quickAddLabelIDs.insert(label.id)
                    }
                })
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: quickAddLabelIDs.isEmpty ? "tag" : "tag.fill")
                if !quickAddLabelIDs.isEmpty {
                    Text("\(quickAddLabelIDs.count)")
                        .font(.system(size: 9 * fs))
                }
            }
            .foregroundStyle(quickAddLabelIDs.isEmpty
                ? app.theme.secondaryStyle
                : AnyShapeStyle(app.theme.accent ?? .accentColor))
        }
        .buttonStyle(.plain)
        .help("Etiquetas de la nueva tarea")
    }

    private func resetQuickAdd() {
        showQuickAdd = false
        quickAddText = ""
        quickAddPriority = "none"
        quickAddLabelIDs = []
    }

    private func submitQuickAdd() {
        let title = quickAddText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !isCreating else { return }
        isCreating = true
        Task {
            let priority = quickAddPriority == "none" ? nil : quickAddPriority
            if await app.createWorkItem(named: title, priority: priority, labelIDs: Array(quickAddLabelIDs)) {
                resetQuickAdd()
            }
            isCreating = false
        }
    }

    @ViewBuilder
    private var projectPicker: some View {
        @Bindable var app = app
        Picker("Proyecto", selection: Binding(
            get: { app.selectedProject?.id ?? "" },
            set: { app.selectedProjectID = $0 }
        )) {
            ForEach(app.visibleProjects) { project in
                Text("\(project.identifier) · \(project.name)").tag(project.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    @ViewBuilder
    private var modulePicker: some View {
        let modules = app.selectedProjectModules
        if !modules.isEmpty {
            Picker("Módulo", selection: Binding(
                get: { app.selectedModuleID ?? "" },
                set: { app.selectedModuleID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Todos los módulos").tag("")
                ForEach(modules) { module in
                    Text(module.name).tag(module.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var cyclePicker: some View {
        let cycles = app.selectedProjectCycles
        if !cycles.isEmpty {
            Picker("Ciclo", selection: Binding(
                get: { app.selectedCycleID ?? "" },
                set: { app.selectedCycleID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Todos los ciclos").tag("")
                ForEach(cycles) { cycle in
                    Text(cycle.name).tag(cycle.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.client == nil {
            hint("Configura el API token y el workspace en Ajustes para empezar.")
        } else if isPortfolio {
            PortfolioBoard(fillsHeight: isWindow)
        } else if app.visibleProjects.isEmpty {
            hint("No hay proyectos visibles. Actívalos en Ajustes.")
        } else {
            VStack(spacing: 0) {
                if let error = app.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if app.kanbanHiddenCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                        Text("\(app.kanbanHiddenCount) tareas ocultas por el filtro «solo mías»")
                        Button("Mostrar todas") { app.settings.onlyMine = false }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    .font(.caption)
                    .foregroundStyle(app.theme.secondaryStyle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if app.settings.boardMode == "gantt" {
                    GanttBoard(fillsHeight: isWindow)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    KanbanBoard(fillsHeight: isWindow)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.callout)
                .foregroundStyle(app.theme.secondaryStyle)
                .multilineTextAlignment(.center)
            Button("Abrir Ajustes") {
                AppWindows.shared.openSettings()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
