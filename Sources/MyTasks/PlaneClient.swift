import Foundation

struct PlaneError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? {
        switch statusCode {
        case 401, 403: "Token inválido o sin permisos (HTTP \(statusCode))"
        case 404: "No encontrado (HTTP 404) — revisa la URL base y el workspace slug"
        case 429: "Rate limit de la API alcanzado (60 req/min)"
        default: "Error de la API de Plane (HTTP \(statusCode)): \(message.prefix(120))"
        }
    }
}

/// Para respuestas cuyo contenido no interesa (p. ej. el eco de module-issues).
private struct IgnoredObject: Decodable {}

struct PlaneClient: Sendable {
    let baseURL: String   // sin barra final, p. ej. https://plane.miempresa.com
    let slug: String
    let token: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Endpoints

    func me() async throws -> UserLite {
        try await request(path: "users/me/")
    }

    func projects() async throws -> [Project] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/")
    }

    func states(projectID: String) async throws -> [WorkItemState] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/states/")
    }

    func labels(projectID: String) async throws -> [WorkItemLabel] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/labels/")
    }

    func members(projectID: String) async throws -> [UserLite] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/members/")
    }

    func workItems(projectID: String) async throws -> [WorkItem] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/work-items/")
    }

    func modules(projectID: String) async throws -> [Module] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/modules/")
    }

    func moduleWorkItems(projectID: String, moduleID: String) async throws -> [WorkItem] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/modules/\(moduleID)/module-issues/")
    }

    func cycles(projectID: String) async throws -> [Cycle] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/cycles/")
    }

    func cycleWorkItems(projectID: String, cycleID: String) async throws -> [WorkItem] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/cycles/\(cycleID)/cycle-issues/")
    }

    func comments(projectID: String, itemID: String) async throws -> [Comment] {
        try await fetchAllPages(path: "workspaces/\(slug)/projects/\(projectID)/work-items/\(itemID)/comments/")
    }

    func createWorkItem(projectID: String, fields: [String: any Sendable]) async throws -> WorkItem {
        let body = try JSONSerialization.data(withJSONObject: fields)
        return try await request(
            method: "POST",
            path: "workspaces/\(slug)/projects/\(projectID)/work-items/",
            body: body
        )
    }

    func addToModule(projectID: String, moduleID: String, itemID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["issues": [itemID]])
        let _: [IgnoredObject] = try await request(
            method: "POST",
            path: "workspaces/\(slug)/projects/\(projectID)/modules/\(moduleID)/module-issues/",
            body: body
        )
    }

    /// PATCH genérico de un work item: `["state": id]`, `["priority": "high"]`,
    /// `["labels": [ids]]`, `["assignees": [ids]]`…
    func updateWorkItem(projectID: String, itemID: String, fields: [String: any Sendable]) async throws {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let _: WorkItem = try await request(
            method: "PATCH",
            path: "workspaces/\(slug)/projects/\(projectID)/work-items/\(itemID)/",
            body: body
        )
    }

    // MARK: - Transporte

    private func request<T: Decodable>(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        var comps = URLComponents(string: "\(baseURL)/api/v1/\(path)")!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "X-API-Key")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PlaneError(statusCode: status, message: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Recorre la paginación por cursor. Acepta tanto el envelope paginado
    /// como una respuesta de array plano (varía entre endpoints/versiones).
    private func fetchAllPages<T: Decodable & Sendable>(path: String) async throws -> [T] {
        var all: [T] = []
        var cursor: String?
        repeat {
            var query = [URLQueryItem(name: "per_page", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            do {
                let page: Page<T> = try await request(path: path, query: query)
                all += page.results
                cursor = (page.nextPageResults == true) ? page.nextCursor : nil
            } catch is DecodingError {
                let plain: [T] = try await request(path: path, query: query)
                return plain
            }
        } while cursor != nil
        return all
    }
}
