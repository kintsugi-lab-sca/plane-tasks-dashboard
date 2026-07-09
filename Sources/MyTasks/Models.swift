import Foundation

struct Project: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let identifier: String
}

struct WorkItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var priority: String
    let sequenceId: Int
    var state: String
    var assignees: [String]
    var labels: [String]
    let project: String
    let startDate: String?
    let targetDate: String?
    let descriptionHtml: String?

    var priorityRank: Int {
        switch priority {
        case "urgent": 0
        case "high": 1
        case "medium": 2
        case "low": 3
        default: 4
        }
    }
}

/// Prioridades de Plane: (valor API, nombre visible) en orden de menú.
enum WorkItemPriority {
    static let options: [(String, String)] = [
        ("urgent", "Urgente"), ("high", "Alta"), ("medium", "Media"),
        ("low", "Baja"), ("none", "Sin prioridad"),
    ]
}

struct WorkItemState: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: String
    let group: String
    let sequence: Double

    // backlog / unstarted / started / completed / cancelled
    var isActive: Bool { group != "completed" && group != "cancelled" }

    var groupRank: Int {
        switch group {
        case "started": 0
        case "unstarted": 1
        case "backlog": 2
        case "completed": 3
        default: 4
        }
    }
}

struct WorkItemLabel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: String?
}

struct Module: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: String?
    let sortOrder: Double?
}

struct Comment: Codable, Identifiable, Sendable {
    let id: String
    let commentHtml: String?
    let actor: String?
    let createdAt: String
}

struct Cycle: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Double?
}

struct UserLite: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String?
}

struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    let results: [T]
    let nextCursor: String?
    let nextPageResults: Bool?
}
