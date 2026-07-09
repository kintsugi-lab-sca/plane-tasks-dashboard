import Foundation

/// Cálculo puro de los difs notificables entre dos refreshes.
/// Separado de AppState para poder testearlo sin Keychain ni red.
enum RefreshDiff {
    struct Alert: Equatable, Sendable {
        let itemID: String
        let title: String
        let body: String
    }

    static func compute(
        projectIdentifier: String,
        old: [WorkItem],
        new: [WorkItem],
        myUserID: String?,
        stateNames: [String: String]
    ) -> [Alert] {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        var alerts: [Alert] = []
        for item in new {
            let code = "\(projectIdentifier)-\(item.sequenceId)"
            guard let previous = oldByID[item.id] else {
                if let me = myUserID, item.assignees.contains(me) {
                    alerts.append(Alert(itemID: item.id, title: "Nueva tarea asignada", body: "\(code) · \(item.name)"))
                }
                continue
            }
            if let me = myUserID, item.assignees.contains(me), !previous.assignees.contains(me) {
                alerts.append(Alert(itemID: item.id, title: "Tarea asignada a ti", body: "\(code) · \(item.name)"))
            }
            if previous.state != item.state {
                let stateName = stateNames[item.state] ?? "otro estado"
                alerts.append(Alert(itemID: item.id, title: "\(code) → \(stateName)", body: item.name))
            }
        }
        return alerts
    }
}
