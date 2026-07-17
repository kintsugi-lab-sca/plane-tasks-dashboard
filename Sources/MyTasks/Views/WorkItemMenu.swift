import SwiftUI

/// Contenido del menú contextual de una tarea, compartido entre las cards del
/// kanban y las barras del gantt. Secciones planas, no Menu anidados: los
/// submenús dentro de .contextMenu meten a SwiftUI en un bucle infinito de
/// invalidación (freeze con CPU al 100%) en macOS 26.
struct WorkItemMenuContent: View {
    @Environment(AppState.self) private var app
    let item: WorkItem

    /// Todos los estados (con Done/Cancelled): desde aquí se cierran tareas.
    private var states: [WorkItemState] { app.allStates }
    private var projectLabels: [WorkItemLabel] { app.labelsByProject[item.project] ?? [] }
    private var projectMembers: [UserLite] { app.membersByProject[item.project] ?? [] }

    var body: some View {
        Button("Abrir en Plane") {
            guard let project = app.selectedProject,
                  let url = app.webURL(for: item, in: project) else { return }
            NSWorkspace.shared.open(url)
        }
        Divider()
        ForEach(states) { state in
            Button {
                Task { await app.changeState(of: item, to: state) }
            } label: {
                if state.id == item.state {
                    Label(state.name, systemImage: "checkmark")
                } else {
                    Text(state.name)
                }
            }
        }
        Section("Prioridad") {
            ForEach(WorkItemPriority.options, id: \.0) { value, name in
                checkmarkButton(name, checked: item.priority == value) {
                    Task { await app.changePriority(of: item, to: value) }
                }
            }
        }
        if !projectLabels.isEmpty {
            Section("Etiquetas") {
                ForEach(projectLabels) { label in
                    checkmarkButton(label.name, checked: item.labels.contains(label.id)) {
                        Task { await app.toggleLabel(label, on: item) }
                    }
                }
            }
        }
        if !projectMembers.isEmpty {
            Section("Asignados") {
                ForEach(projectMembers) { member in
                    checkmarkButton(member.displayName ?? member.id, checked: item.assignees.contains(member.id)) {
                        Task { await app.toggleAssignee(member, on: item) }
                    }
                }
            }
        }
    }

    private func checkmarkButton(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
