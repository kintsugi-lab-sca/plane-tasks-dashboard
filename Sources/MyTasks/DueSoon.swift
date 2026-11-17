import Foundation

/// Avisos de vencimiento (puro, testeable): tareas activas cuya fecha límite
/// es hoy o mañana. La deduplicación usa claves "itemID|fecha" persistidas por
/// el llamador: una tarea se avisa una vez por fecha límite — si se reprograma,
/// vuelve a avisar con la fecha nueva.
enum DueSoon {
    struct Alert: Equatable {
        let itemID: String
        let title: String
        let body: String
        /// Clave de dedupe: "itemID|targetDate".
        let dueKey: String
    }

    static func compute(
        projectIdentifier: String,
        items: [WorkItem],
        todayISO: String,
        tomorrowISO: String,
        alreadyNotified: Set<String>
    ) -> [Alert] {
        items.compactMap { item in
            guard let target = item.targetDate else { return nil }
            let title: String
            switch target {
            case todayISO: title = "Vence hoy"
            case tomorrowISO: title = "Vence mañana"
            default: return nil
            }
            let key = "\(item.id)|\(target)"
            guard !alreadyNotified.contains(key) else { return nil }
            return Alert(
                itemID: item.id,
                title: title,
                body: "\(projectIdentifier)-\(item.sequenceId) · \(item.name)",
                dueKey: key
            )
        }
    }

    /// Avisos de hitos de las fichas del portafolio que caen hoy o mañana:
    /// fechas pactadas que no son tareas de Plane. Misma deduplicación que las
    /// tareas, con clave "hito:slug:etiqueta|fecha" (compatible con `prune`).
    static func milestoneAlerts(
        entries: [PortfolioEntry],
        todayISO: String,
        tomorrowISO: String,
        alreadyNotified: Set<String>
    ) -> [Alert] {
        entries.filter { !$0.archived }.flatMap { entry in
            entry.dates.compactMap { milestone -> Alert? in
                let title: String
                switch milestone.date {
                case todayISO: title = "Hito hoy"
                case tomorrowISO: title = "Hito mañana"
                default: return nil
                }
                let label = milestone.label.replacingOccurrences(of: "|", with: "/")
                let key = "hito:\(entry.slug):\(label)|\(milestone.date)"
                guard !alreadyNotified.contains(key) else { return nil }
                return Alert(itemID: entry.slug, title: title, body: "\(entry.name) · \(milestone.label)", dueKey: key)
            }
        }
    }

    /// Poda las claves de fechas ya pasadas (la comparación lexicográfica de
    /// "yyyy-MM-dd" es cronológica); una clave malformada se descarta.
    static func prune(_ keys: Set<String>, todayISO: String) -> Set<String> {
        keys.filter { key in
            guard let separator = key.firstIndex(of: "|") else { return false }
            return String(key[key.index(after: separator)...]) >= todayISO
        }
    }
}
