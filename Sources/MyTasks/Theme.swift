import SwiftUI

struct Theme: Identifiable {
    let id: String
    let name: String
    var colorScheme: ColorScheme?
    var accent: Color?
    var background: Color?
    var surface: Color?
    var card: Color?
    var cardBorder: Color?
    var textPrimary: Color?
    var textSecondary: Color?
    var monospaced = false

    // MARK: - Temas predefinidos

    static let system = Theme(id: "system", name: "Sistema", colorScheme: nil)

    static let kintsugi = Theme(
        id: "kintsugi", name: "Kintsugi", colorScheme: .light,
        accent: Color(rgb: 0xC9962E),
        background: Color(rgb: 0xF7F3EC),
        surface: Color(rgb: 0xEDE5D6),
        card: Color(rgb: 0xFFFFFF),
        cardBorder: Color(rgb: 0xC9962E).opacity(0.25),
        textPrimary: Color(rgb: 0x2B2622),
        textSecondary: Color(rgb: 0x8A7F6E)
    )

    static let midnight = Theme(
        id: "midnight", name: "Medianoche", colorScheme: .dark,
        accent: Color(rgb: 0x7C8CF8),
        background: Color(rgb: 0x10121A),
        surface: Color(rgb: 0x181B26),
        card: Color(rgb: 0x222634),
        cardBorder: Color(rgb: 0x7C8CF8).opacity(0.2),
        textPrimary: Color(rgb: 0xE8EAF2),
        textSecondary: Color(rgb: 0x9AA1B5)
    )

    static let hacker = Theme(
        id: "hacker", name: "Hacker", colorScheme: .dark,
        accent: Color(rgb: 0x33FF66),
        background: Color(rgb: 0x050905),
        surface: Color(rgb: 0x0B140B),
        card: Color(rgb: 0x0E1A0E),
        cardBorder: Color(rgb: 0x33FF66).opacity(0.35),
        textPrimary: Color(rgb: 0x4AFF7E),
        textSecondary: Color(rgb: 0x2BB157),
        monospaced: true
    )

    static let all: [Theme] = [.system, .kintsugi, .midnight, .hacker]

    static func builtin(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .system
    }

    // MARK: - Estilos con fallback al sistema (tema "Sistema" → todo nil)

    var primaryStyle: AnyShapeStyle {
        textPrimary.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
    }

    var secondaryStyle: AnyShapeStyle {
        textSecondary.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
    }

    var cardStyle: AnyShapeStyle {
        card.map(AnyShapeStyle.init) ?? AnyShapeStyle(.background)
    }

    var cardBorderStyle: AnyShapeStyle {
        cardBorder.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary)
    }

    var surfaceColor: Color {
        surface ?? Color.primary.opacity(0.05)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// "#RRGGBB" del color en sRGB; nil si no es convertible.
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(c.redComponent * 255)),
            Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255))
        )
    }
}
