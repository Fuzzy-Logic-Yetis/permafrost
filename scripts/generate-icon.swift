// Generates Resources/AppIcon.icns's source PNGs: an icy-blue squircle with a bold
// white snowflake glyph, at every size macOS expects in an .iconset.
//
// Usage: swift scripts/generate-icon.swift <output-iconset-dir>
//        iconutil -c icns <output-iconset-dir> -o Resources/AppIcon.icns
//
// Only needs re-running if the icon design itself changes — the .icns is committed
// as a binary resource, not regenerated on every build.
import AppKit
import CoreGraphics

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments[1]

func drawIcon(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let full = CGRect(x: 0, y: 0, width: px, height: px)
    // macOS-style squircle-ish rounded rect (~22% corner radius of full bleed square).
    let corner = CGFloat(px) * 0.225
    let path = CGPath(roundedRect: full, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Icy blue gradient background, deep blue at bottom to light frost at top.
    let colors = [
        CGColor(red: 0.62, green: 0.86, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.12, green: 0.42, blue: 0.68, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: px / 2, y: px),
        end: CGPoint(x: px / 2, y: 0),
        options: []
    )

    // Subtle inner highlight near the top for a glassy feel.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    let highlight = CGRect(x: 0, y: CGFloat(px) * 0.55, width: CGFloat(px), height: CGFloat(px) * 0.45)
    ctx.fillEllipse(in: highlight.insetBy(dx: -CGFloat(px) * 0.15, dy: 0))

    NSGraphicsContext.restoreGraphicsState()

    // Snowflake glyph, centered, drawn via a fresh context pointed at the same rep.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let symbolPointSize = CGFloat(px) * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let imgRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: imgRect)
        imgRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawSize = symbol.size
        let origin = NSPoint(x: (CGFloat(px) - drawSize.width) / 2, y: (CGFloat(px) - drawSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    NSGraphicsContext.restoreGraphicsState()

    return rep
}

for (name, px) in sizes {
    let rep = drawIcon(px: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to encode \(name)")
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try! data.write(to: url)
    print("wrote \(url.path)")
}
