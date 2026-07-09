import Foundation

struct AppSettings: Sendable, Equatable {
    var baseURL: String
    var workspaceSlug: String
    var visibleProjectIDs: Set<String>
    var onlyMine: Bool
    var notifyChanges: Bool
    /// Contador del icono: "all" (todas), "urgent" (solo urgentes) u "hidden".
    var badgeMode: String
    /// Id del atajo global (ver HotKey.options); "none" = desactivado.
    var hotKeyID: String
    var refreshMinutes: Int
    var themeID: String
    var fontScale: Double
    var accentHex: String?
    var backgroundHex: String?
    var surfaceHex: String?
    var cardHex: String?

    static func load() -> AppSettings {
        let d = UserDefaults.standard
        return AppSettings(
            baseURL: d.string(forKey: "baseURL") ?? "",
            workspaceSlug: d.string(forKey: "workspaceSlug") ?? "",
            visibleProjectIDs: Set(d.stringArray(forKey: "visibleProjectIDs") ?? []),
            onlyMine: d.object(forKey: "onlyMine") as? Bool ?? true,
            notifyChanges: d.bool(forKey: "notifyChanges"),
            badgeMode: d.string(forKey: "badgeMode") ?? "all",
            hotKeyID: d.string(forKey: "hotKeyID") ?? "none",
            refreshMinutes: max(1, d.integer(forKey: "refreshMinutes") == 0 ? 5 : d.integer(forKey: "refreshMinutes")),
            themeID: d.string(forKey: "themeID") ?? "system",
            fontScale: d.double(forKey: "fontScale") == 0 ? 1.0 : d.double(forKey: "fontScale"),
            accentHex: d.string(forKey: "accentHex"),
            backgroundHex: d.string(forKey: "backgroundHex"),
            surfaceHex: d.string(forKey: "surfaceHex"),
            cardHex: d.string(forKey: "cardHex")
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: "baseURL")
        d.set(workspaceSlug, forKey: "workspaceSlug")
        d.set(Array(visibleProjectIDs), forKey: "visibleProjectIDs")
        d.set(onlyMine, forKey: "onlyMine")
        d.set(notifyChanges, forKey: "notifyChanges")
        d.set(badgeMode, forKey: "badgeMode")
        d.set(hotKeyID, forKey: "hotKeyID")
        d.set(refreshMinutes, forKey: "refreshMinutes")
        d.set(themeID, forKey: "themeID")
        d.set(fontScale, forKey: "fontScale")
        d.set(accentHex, forKey: "accentHex")
        d.set(backgroundHex, forKey: "backgroundHex")
        d.set(surfaceHex, forKey: "surfaceHex")
        d.set(cardHex, forKey: "cardHex")
    }

    /// URL base normalizada, sin barra final.
    var normalizedBaseURL: String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }
}
