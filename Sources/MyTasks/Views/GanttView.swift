import SwiftUI

/// Nombres de símbolo con fallback: "chart.gantt" no existe hasta macOS 15
/// y el target de despliegue es macOS 14.
enum GanttSymbols {
    static let gantt: String =
        NSImage(systemSymbolName: "chart.gantt", accessibilityDescription: nil) != nil
            ? "chart.gantt" : "calendar.day.timeline.left"
}

/// Presets de zoom del cronograma (puntos por día, antes de fontScale).
/// El zoom real es continuo (pinch / ⌘+scroll); los presets son atajos.
enum GanttZoom: String, CaseIterable, Identifiable {
    case day, week, month, quarter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "Día"
        case .week: "Semana"
        case .month: "Mes"
        case .quarter: "Trimestre"
        }
    }

    var dayWidth: CGFloat {
        switch self {
        case .day: 42
        case .week: 17
        case .month: 6.5
        case .quarter: 3
        }
    }
}

/// Monitor local de rueda/trackpad: convierte ⌘+scroll en zoom del gantt.
/// Clase aparte porque el closure de NSEvent no es MainActor y necesita
/// assumeIsolated; `isEnabled` lo gobierna el hover del cronograma (así, con
/// panel y ventana abiertos a la vez, solo consume eventos el que está bajo
/// el cursor).
@MainActor
final class GanttScrollZoomMonitor {
    var isEnabled = false
    var onZoom: ((CGFloat) -> Void)?
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let command = event.modifierFlags.contains(.command)
            let delta = event.scrollingDeltaY
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isEnabled, command, delta != 0 else { return false }
                self.onZoom?(exp2(delta * 0.015))
                return true
            }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

/// Posición de scroll del cronograma, fuera del ciclo de render: el offset
/// cambia en cada frame de scroll y observarlo como @State re-renderizaría
/// todo el tablero continuamente. Solo lo leen los gestos de zoom.
final class GanttScrollMetrics: @unchecked Sendable {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
}

private struct GanttScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Vista de cronograma (gantt): eje temporal horizontal con cabecera de
/// meses/días, sombreado de fines de semana, línea de "hoy", barras
/// arrastrables para reprogramar fechas y bandeja de tareas sin fechas.
struct GanttBoard: View {
    @Environment(AppState.self) private var app
    /// true en la ventana redimensionable (ocupa todo el alto disponible);
    /// false en el panel de la barra de menú (alto fijo).
    var fillsHeight = false

    /// Puntos por día (antes de fontScale). Continuo: pinch y ⌘+scroll lo
    /// modulan; los presets de la píldora lo fijan a valores conocidos.
    @State private var dayWidth: CGFloat = GanttZoom.week.dayWidth
    @State private var trayCollapsed = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var pendingScrollToToday = false
    @State private var pinchBase: CGFloat?
    @State private var pinchAnchorWeek: Int?
    @State private var metrics = GanttScrollMetrics()
    @State private var zoomMonitor = GanttScrollZoomMonitor()
    @Namespace private var zoomNS

    /// Rango del zoom continuo (pre-fontScale).
    private static let zoomRange: ClosedRange<CGFloat> = 2.5...48

    private static func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var accent: Color { app.theme.accent ?? .accentColor }

    /// Alto del tablero en el panel: mismo criterio que el kanban
    /// (mitad del alto visible de la pantalla, mínimo 448 pt).
    private var panelBoardHeight: CGFloat {
        max(448, (NSScreen.main?.visibleFrame.height ?? 900) * 0.5)
    }

    var body: some View {
        let layout = GanttLayout.make(items: app.ganttItems, dayWidth: dayWidth * fs)
        VStack(spacing: 0) {
            if layout.rows.isEmpty && layout.unscheduled.isEmpty {
                emptyState
            } else {
                timeline(layout)
                    .overlay(alignment: .bottomTrailing) { zoomPill }
                if !layout.unscheduled.isEmpty {
                    unscheduledTray(layout.unscheduled)
                }
            }
        }
        .frame(height: fillsHeight ? nil : panelBoardHeight)
        .frame(maxHeight: fillsHeight ? .infinity : panelBoardHeight)
    }

    // MARK: - Timeline

    private func timeline(_ layout: GanttLayout) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    weekAnchors(layout)
                    gridCanvas(layout)
                    VStack(spacing: 0) {
                        headerCanvas(layout)
                        Divider().opacity(0.35)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, row in
                                    GanttRowView(row: row, layout: layout, index: index)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .frame(width: layout.totalWidth)
                    todayOverlay(layout)
                }
                .frame(width: layout.totalWidth)
                .background(GeometryReader { g in
                    Color.clear.preference(
                        key: GanttScrollOffsetKey.self,
                        value: -g.frame(in: .named("gantt-scroll")).minX
                    )
                })
            }
            .coordinateSpace(name: "gantt-scroll")
            .onPreferenceChange(GanttScrollOffsetKey.self) { [metrics] value in
                metrics.offset = value
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { metrics.viewport = g.size.width }
                    .onChange(of: g.size.width) { _, width in metrics.viewport = width }
            })
            .simultaneousGesture(magnifyGesture(layout, proxy))
            .onHover { zoomMonitor.isEnabled = $0 }
            .onAppear {
                scrollProxy = proxy
                scrollToToday(proxy, layout)
                zoomMonitor.onZoom = { factor in handleScrollZoom(factor) }
                zoomMonitor.install()
            }
            .onDisappear { zoomMonitor.remove() }
            .onChange(of: dayWidth) {
                guard pendingScrollToToday else { return }
                pendingScrollToToday = false
                DispatchQueue.main.async { scrollToToday(proxy, layout) }
            }
        }
    }

    /// Marcadores invisibles por semana: dan a ScrollViewReader un id al que
    /// saltar (el resto del contenido se posiciona por offset, sin ids).
    private func weekAnchors(_ layout: GanttLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<(layout.dayCount / 7), id: \.self) { week in
                Color.clear
                    .frame(width: layout.dayWidth * 7, height: 1)
                    .id("gantt-week-\(week)")
            }
        }
    }

    private func scrollToToday(_ proxy: ScrollViewProxy, _ layout: GanttLayout) {
        let week = Int(layout.x(layout.today) / layout.dayWidth) / 7
        proxy.scrollTo("gantt-week-\(week)", anchor: UnitPoint(x: 0.25, y: 0))
    }

    // MARK: - Cabecera y rejilla (Canvas: cientos de ticks sin coste de views)

    private var headerSecondary: Color {
        app.theme.textSecondary ?? Color(nsColor: .secondaryLabelColor)
    }

    private func headerCanvas(_ layout: GanttLayout) -> some View {
        let fs = fs
        let secondary = headerSecondary
        return Canvas { ctx, size in
            let monthFormatter = DateFormatter()
            // Con el zoom muy alejado (trimestre) el nombre largo no cabe.
            monthFormatter.setLocalizedDateFormatFromTemplate(layout.dayWidth < 5 ? "MMM yy" : "MMMM yyyy")
            let weekFormatter = DateFormatter()
            weekFormatter.setLocalizedDateFormatFromTemplate("d MMM")

            for tick in layout.monthTicks {
                if tick.x > 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: tick.x, y: 0))
                    line.addLine(to: CGPoint(x: tick.x, y: size.height))
                    ctx.stroke(line, with: .color(.primary.opacity(0.12)), lineWidth: 1)
                }
                // Solo la primera letra en mayúscula ("Agosto de 2026", no "Agosto De 2026").
                let raw = monthFormatter.string(from: tick.month)
                let label = raw.prefix(1).localizedUppercase + raw.dropFirst()
                ctx.draw(
                    Text(label).font(.system(size: 10 * fs, weight: .semibold)).foregroundStyle(secondary),
                    at: CGPoint(x: tick.x + 8, y: 9 * fs), anchor: .leading
                )
            }
            if layout.dayWidth >= 24 {
                for i in 0..<layout.dayCount {
                    let date = layout.day(i)
                    let cx = (CGFloat(i) + 0.5) * layout.dayWidth
                    let dim = layout.isWeekend(date)
                    ctx.draw(
                        Text("\(layout.calendar.component(.day, from: date))")
                            .font(.system(size: 9 * fs, weight: .medium).monospacedDigit())
                            .foregroundStyle(dim ? secondary.opacity(0.45) : secondary),
                        at: CGPoint(x: cx, y: 27 * fs)
                    )
                }
            } else if layout.dayWidth >= 8 {
                for tick in layout.weekTicks {
                    ctx.draw(
                        Text(weekFormatter.string(from: tick.monday))
                            .font(.system(size: 8.5 * fs).monospacedDigit())
                            .foregroundStyle(secondary.opacity(0.85)),
                        at: CGPoint(x: tick.x + 4, y: 27 * fs), anchor: .leading
                    )
                }
            }
        }
        .frame(width: layout.totalWidth, height: 36 * fs)
    }

    private func gridCanvas(_ layout: GanttLayout) -> some View {
        Canvas { ctx, size in
            if layout.dayWidth >= 8 {
                for i in 0..<layout.dayCount where layout.isWeekend(layout.day(i)) {
                    let band = CGRect(x: CGFloat(i) * layout.dayWidth, y: 0, width: layout.dayWidth, height: size.height)
                    ctx.fill(Path(band), with: .color(.primary.opacity(0.035)))
                }
                for tick in layout.weekTicks where tick.x > 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: tick.x, y: 0))
                    line.addLine(to: CGPoint(x: tick.x, y: size.height))
                    ctx.stroke(line, with: .color(.primary.opacity(0.05)), lineWidth: 1)
                }
            }
            for tick in layout.monthTicks where tick.x > 0 {
                var line = Path()
                line.move(to: CGPoint(x: tick.x, y: 0))
                line.addLine(to: CGPoint(x: tick.x, y: size.height))
                ctx.stroke(line, with: .color(.primary.opacity(0.09)), lineWidth: 1)
            }
        }
        .frame(width: layout.totalWidth)
        .frame(maxHeight: .infinity)
    }

    /// Línea vertical de "hoy" con chip en la cabecera, cruzando todo el alto.
    private func todayOverlay(_ layout: GanttLayout) -> some View {
        let cx = layout.x(layout.today) + layout.dayWidth / 2
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .shadow(color: accent.opacity(0.7), radius: 3)
                .offset(x: cx - 0.75)
            Text("HOY")
                .font(.system(size: 7.5 * fs, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(accent, in: Capsule())
                .shadow(color: accent.opacity(0.55), radius: 4, y: 1)
                .frame(width: 64)
                .offset(x: cx - 32, y: 2)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Zoom

    /// Preset más cercano al zoom continuo actual (para resaltar la píldora).
    private var nearestPreset: GanttZoom {
        GanttZoom.allCases.min {
            abs($0.dayWidth - dayWidth) < abs($1.dayWidth - dayWidth)
        } ?? .week
    }

    /// Semana del eje que está en el centro del viewport (ancla del zoom).
    private func centerWeek(_ layout: GanttLayout) -> Int {
        let centerX = metrics.offset + metrics.viewport / 2
        let day = max(0, min(layout.dayCount - 1, Int(centerX / layout.dayWidth)))
        return day / 7
    }

    /// Pinch en el trackpad: zoom continuo anclado al centro visible.
    private func magnifyGesture(_ layout: GanttLayout, _ proxy: ScrollViewProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil {
                    pinchBase = dayWidth
                    pinchAnchorWeek = centerWeek(layout)
                }
                dayWidth = Self.clampZoom((pinchBase ?? dayWidth) * value.magnification)
                if let week = pinchAnchorWeek {
                    proxy.scrollTo("gantt-week-\(week)", anchor: .center)
                }
            }
            .onEnded { _ in
                pinchBase = nil
                pinchAnchorWeek = nil
            }
    }

    /// ⌘+scroll (rueda o trackpad): mismo zoom continuo que el pinch.
    private func handleScrollZoom(_ factor: CGFloat) {
        let layout = GanttLayout.make(items: app.ganttItems, dayWidth: dayWidth * fs)
        let week = centerWeek(layout)
        dayWidth = Self.clampZoom(dayWidth * factor)
        scrollProxy?.scrollTo("gantt-week-\(week)", anchor: .center)
    }

    private var zoomPill: some View {
        HStack(spacing: 2) {
            ForEach(GanttZoom.allCases) { level in
                Button {
                    pendingScrollToToday = true
                    withAnimation(.snappy(duration: 0.25)) { dayWidth = level.dayWidth }
                } label: {
                    Text(level.label)
                        .font(.system(size: 10 * fs, weight: .semibold))
                        .foregroundStyle(nearestPreset == level ? AnyShapeStyle(accent) : app.theme.secondaryStyle)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            if nearestPreset == level {
                                Capsule()
                                    .fill(app.theme.cardStyle)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "gantt-zoom", in: zoomNS)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Escala: \(level.label.lowercased()) — pinch o ⌘+scroll para zoom fino")
            }
        }
        .padding(3)
        .glassPill()
        .padding(.trailing, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Bandeja "sin fechas" y estado vacío

    private func unscheduledTray(_ items: [WorkItem]) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                withAnimation(.snappy(duration: 0.2)) { trayCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 10 * fs))
                    Text("Sin fechas")
                        .font(.system(size: 11 * fs, weight: .medium))
                    Text("\(items.count)")
                        .font(.system(size: 9 * fs).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8 * fs, weight: .semibold))
                        .rotationEffect(.degrees(trayCollapsed ? -90 : 0))
                    Spacer()
                }
                .foregroundStyle(app.theme.secondaryStyle)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if !trayCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            UnscheduledChip(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: GanttSymbols.gantt)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Sin tareas en el cronograma")
                .font(.system(size: 13 * fs, weight: .semibold))
            Text("Las tareas aparecen aquí con sus fechas de inicio y límite.")
                .font(.system(size: 11 * fs))
                .foregroundStyle(app.theme.secondaryStyle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Fila del cronograma

private struct GanttRowView: View {
    @Environment(AppState.self) private var app
    let row: GanttLayout.Row
    let layout: GanttLayout
    let index: Int

    @State private var hovering = false
    @State private var shapeHovering = false
    @State private var showDetail = false
    @State private var appeared = false
    /// Desplazamiento en días durante un arrastre (snap a día).
    @State private var dragDays = 0
    /// Cambio de duración en días durante un resize por el borde derecho.
    @State private var resizeDays = 0
    @State private var dragging = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var rowHeight: CGFloat { 30 * fs }
    private var barHeight: CGFloat { 19 * fs }
    private var stateColor: Color { Color(hex: app.state(of: row.item)?.color) ?? .gray }

    var body: some View {
        let base = layout.frame(for: row.kind)
        let x = base.x + CGFloat(dragDays) * layout.dayWidth
        let width = max(layout.dayWidth, base.width + CGFloat(resizeDays) * layout.dayWidth)
        let labelInside = isBar && width > 150 * fs

        ZStack(alignment: .leading) {
            Color.primary.opacity(hovering ? 0.035 : 0)
            shape(width: width, labelInside: labelInside)
                .scaleEffect(x: appeared ? 1 : 0.4, y: 1, anchor: .leading)
                .offset(x: x)
            if !labelInside {
                label(inside: false)
                    .offset(x: x + width + 8)
            }
            if dragging {
                dateBubble
                    .offset(x: max(0, x), y: -(rowHeight / 2 + 2))
            }
        }
        .frame(width: layout.totalWidth, height: rowHeight, alignment: .leading)
        .zIndex(dragging ? 10 : 0)
        .opacity(appeared ? 1 : 0)
        .onHover { hovering = $0 }
        .onAppear {
            // Entrada escalonada: cada barra crece desde su borde izquierdo.
            withAnimation(.snappy(duration: 0.4).delay(min(Double(index) * 0.025, 0.35))) {
                appeared = true
            }
        }
    }

    private var isBar: Bool {
        if case .bar = row.kind { return true }
        return false
    }

    @ViewBuilder
    private func shape(width: CGFloat, labelInside: Bool) -> some View {
        switch row.kind {
        case .bar:
            interactive(barBody(width: width, labelInside: labelInside, fade: false))
        case .openEnded:
            interactive(barBody(width: width, labelInside: labelInside, fade: true))
        case .milestone:
            interactive(milestoneBody(width: width))
        }
    }

    /// Interacción común de las figuras: hover con elevación, tap → detalle,
    /// drag → mover fechas, menú contextual compartido con el kanban.
    private func interactive(_ content: some View) -> some View {
        content
            .shadow(
                color: .black.opacity(shapeHovering ? 0.25 : 0.10),
                radius: shapeHovering ? 6 : 2, y: shapeHovering ? 3 : 1
            )
            .scaleEffect(shapeHovering ? 1.02 : 1, anchor: .leading)
            .animation(.snappy(duration: 0.15), value: shapeHovering)
            .onHover { shapeHovering = $0 }
            .onTapGesture { showDetail = true }
            .gesture(moveGesture)
            .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                WorkItemDetailView(item: row.item)
            }
            .contextMenu { WorkItemMenuContent(item: row.item) }
            .help(helpText)
    }

    /// Barra con gradiente del color del estado; `fade` desvanece el extremo
    /// derecho (tarea sin fecha límite, abierta hasta hoy).
    private func barBody(width: CGFloat, labelInside: Bool, fade: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(
                colors: [stateColor.opacity(0.72), stateColor],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(stateColor.opacity(0.45), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if labelInside {
                    label(inside: true)
                        .padding(.horizontal, 8)
                }
            }
            .overlay(alignment: .trailing) {
                if isOverdue {
                    Circle()
                        .fill(.red)
                        .frame(width: 6 * fs, height: 6 * fs)
                        .shadow(color: .red.opacity(0.8), radius: 3)
                        .offset(x: 3 * fs)
                }
            }
            .mask {
                if fade {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.75),
                            .init(color: .black.opacity(0.05), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                } else {
                    Rectangle()
                }
            }
            .overlay(alignment: .trailing) {
                if isBar { resizeHandle }
            }
            .frame(width: width, height: barHeight)
    }

    /// Hito: rombo centrado en su fecha.
    private func milestoneBody(width: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [stateColor.opacity(0.75), stateColor],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: barHeight * 0.62, height: barHeight * 0.62)
            .rotationEffect(.degrees(45))
            .overlay {
                if isOverdue {
                    Rectangle()
                        .strokeBorder(.red, lineWidth: 1.5)
                        .frame(width: barHeight * 0.62, height: barHeight * 0.62)
                        .rotationEffect(.degrees(45))
                        .shadow(color: .red.opacity(0.6), radius: 3)
                }
            }
            .frame(width: width, height: barHeight)
    }

    /// Asa invisible en el borde derecho: arrastra para cambiar la fecha límite.
    private var resizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(resizeGesture)
    }

    private func label(inside: Bool) -> some View {
        let luminance = GanttLayout.luminance(hex: app.state(of: row.item)?.color)
        let textColor: Color = luminance > 0.55 ? .black.opacity(0.78) : .white
        return HStack(spacing: 5) {
            if row.item.priority == "urgent" || row.item.priority == "high" {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8 * fs))
                    .foregroundStyle(row.item.priority == "urgent" ? .red : .orange)
            }
            Text("\(app.selectedProject?.identifier ?? "")-\(row.item.sequenceId)")
                .font(.system(size: 8.5 * fs, design: .monospaced))
                .foregroundStyle(inside ? AnyShapeStyle(textColor.opacity(0.75)) : app.theme.secondaryStyle)
            Text(row.item.name)
                .font(.system(size: 10.5 * fs, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(inside ? AnyShapeStyle(textColor) : app.theme.primaryStyle)
            AssigneeBadges(item: row.item, size: 13 * fs)
        }
    }

    /// Cápsula flotante con las fechas resultantes mientras se arrastra.
    private var dateBubble: some View {
        Text(bubbleText)
            .font(.system(size: 9 * fs, weight: .medium).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private var bubbleText: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        switch row.kind {
        case let .bar(start, end):
            let s = layout.adding(dragDays, to: start)
            let e = layout.adding(dragDays + resizeDays, to: end)
            return "\(f.string(from: s)) → \(f.string(from: max(s, e)))"
        case let .milestone(date):
            return "→ \(f.string(from: layout.adding(dragDays, to: date)))"
        case let .openEnded(start):
            return "\(f.string(from: layout.adding(dragDays, to: start))) →"
        }
    }

    private var isOverdue: Bool {
        switch row.kind {
        case let .bar(_, end): end < layout.today
        case let .milestone(date): date < layout.today
        case .openEnded: false
        }
    }

    // MARK: - Gestos (mover y redimensionar con snap a día)

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragging = true
                dragDays = Int((value.translation.width / layout.dayWidth).rounded())
            }
            .onEnded { _ in commitMove() }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard case let .bar(start, end) = row.kind else { return }
                dragging = true
                let duration = layout.calendar.dateComponents([.day], from: start, to: end).day ?? 0
                resizeDays = max(-duration, Int((value.translation.width / layout.dayWidth).rounded()))
            }
            .onEnded { _ in commitResize() }
    }

    private func commitMove() {
        let days = dragDays
        dragging = false
        dragDays = 0
        guard days != 0 else { return }
        let cal = layout.calendar
        switch row.kind {
        case let .bar(start, end):
            let s = GanttLayout.isoString(layout.adding(days, to: start), calendar: cal)
            let t = GanttLayout.isoString(layout.adding(days, to: end), calendar: cal)
            Task { await app.changeDates(of: row.item, start: s, target: t) }
        case let .milestone(date):
            let t = GanttLayout.isoString(layout.adding(days, to: date), calendar: cal)
            Task { await app.changeDates(of: row.item, target: t) }
        case let .openEnded(start):
            let s = GanttLayout.isoString(layout.adding(days, to: start), calendar: cal)
            Task { await app.changeDates(of: row.item, start: s) }
        }
    }

    private func commitResize() {
        let days = resizeDays
        dragging = false
        resizeDays = 0
        guard days != 0, case let .bar(_, end) = row.kind else { return }
        let t = GanttLayout.isoString(layout.adding(days, to: end), calendar: layout.calendar)
        Task { await app.changeDates(of: row.item, target: t) }
    }

    private var helpText: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        switch row.kind {
        case let .bar(start, end):
            let days = (layout.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
            return "\(row.item.name)\n\(f.string(from: start)) – \(f.string(from: end)) · \(days) día\(days == 1 ? "" : "s")"
        case let .milestone(date):
            return "\(row.item.name)\nFecha límite: \(f.string(from: date))"
        case let .openEnded(start):
            return "\(row.item.name)\nDesde \(f.string(from: start)), sin fecha límite"
        }
    }
}

// MARK: - Chip de tarea sin fechas

private struct UnscheduledChip: View {
    @Environment(AppState.self) private var app
    let item: WorkItem

    @State private var hovering = false
    @State private var showDetail = false

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: app.state(of: item)?.color) ?? .gray)
                .frame(width: 6 * fs, height: 6 * fs)
            Text("\(app.selectedProject?.identifier ?? "")-\(item.sequenceId)")
                .font(.system(size: 8.5 * fs, design: .monospaced))
                .foregroundStyle(app.theme.secondaryStyle)
            Text(item.name)
                .font(.system(size: 10.5 * fs))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(app.theme.cardStyle, in: Capsule())
        .overlay(Capsule().strokeBorder(app.theme.cardBorderStyle))
        .background(Color.primary.opacity(hovering ? 0.05 : 0), in: Capsule())
        .frame(maxWidth: 240)
        .onHover { hovering = $0 }
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) {
            WorkItemDetailView(item: item)
        }
        .contextMenu { WorkItemMenuContent(item: item) }
    }
}

// MARK: - Liquid glass con fallback

private extension View {
    /// Cápsula "liquid glass" (macOS 26) con fallback a material translúcido.
    @ViewBuilder
    func glassPill() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}
