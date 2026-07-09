// Genera el icono de la app (1024x1024 PNG): squircle oscuro con
// columnas kanban y una grieta kintsugi dorada. Uso: swift scripts/make_icon.swift <salida.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext

func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Squircle de fondo con degradado oscuro
let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = rounded(bg, 185)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1B1F2E), color(0x0C0E15)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: S / 2, y: bg.maxY),
    end: CGPoint(x: S / 2, y: bg.minY),
    options: []
)

// Grieta kintsugi: polilínea dorada con brillo, detrás de las columnas
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 36, color: color(0xC9962E, 0.75))
ctx.setStrokeColor(color(0xD9A83C))
ctx.setLineWidth(13)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
let crack: [CGPoint] = [
    CGPoint(x: 100, y: 690),
    CGPoint(x: 300, y: 610),
    CGPoint(x: 420, y: 660),
    CGPoint(x: 560, y: 470),
    CGPoint(x: 700, y: 500),
    CGPoint(x: 820, y: 360),
    CGPoint(x: 924, y: 330),
]
ctx.addLines(between: crack)
ctx.strokePath()
// Ramita secundaria de la grieta
ctx.setLineWidth(7)
ctx.addLines(between: [CGPoint(x: 560, y: 470), CGPoint(x: 620, y: 340), CGPoint(x: 600, y: 240)])
ctx.strokePath()
ctx.restoreGState()

// Columnas kanban con tarjetas
struct Column {
    let x: CGFloat
    let height: CGFloat
    let cards: [(UInt32, CGFloat)] // (color, alpha)
}
let columns: [Column] = [
    Column(x: 182, height: 430, cards: [(0xE8EAF2, 0.92), (0xE8EAF2, 0.55)]),
    Column(x: 412, height: 540, cards: [(0xC9962E, 1.0), (0xE8EAF2, 0.75), (0xE8EAF2, 0.4)]),
    Column(x: 642, height: 360, cards: [(0xE8EAF2, 0.85)]),
]
let colWidth: CGFloat = 200
let colTop: CGFloat = 800
for col in columns {
    let rect = CGRect(x: col.x, y: colTop - col.height, width: colWidth, height: col.height)
    ctx.setFillColor(color(0xFFFFFF, 0.08))
    ctx.addPath(rounded(rect, 26))
    ctx.fillPath()

    var cardY = rect.maxY - 20 - 86
    for (rgb, alpha) in col.cards {
        let card = CGRect(x: rect.minX + 20, y: cardY, width: colWidth - 40, height: 86)
        ctx.setFillColor(color(rgb, alpha))
        ctx.addPath(rounded(card, 16))
        ctx.fillPath()
        cardY -= 86 + 18
    }
}
ctx.restoreGState()

// Borde interior sutil del squircle
ctx.addPath(rounded(bg.insetBy(dx: 3, dy: 3), 182))
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(6)
ctx.strokePath()

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("OK → \(out)")
