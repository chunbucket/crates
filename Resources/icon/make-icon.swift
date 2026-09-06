// Renders Resources/Cuts.icns (+ a 512px preview) from code, so the icon
// stays in step with the app's vinyl glyph. Run: swift Resources/icon/make-icon.swift
import AppKit

func draw(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    let r = NSRect(x: 0, y: 0, width: s, height: s)

    // macOS icon plate: rounded square, deep charcoal with a faint top light.
    let plate = NSBezierPath(roundedRect: r.insetBy(dx: s * 0.05, dy: s * 0.05), xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(colors: [NSColor(white: 0.16, alpha: 1), NSColor(white: 0.09, alpha: 1)])!
        .draw(in: plate, angle: -90)

    // Drop shadow under the record.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    let discRect = r.insetBy(dx: s * 0.14, dy: s * 0.14)
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(ovalIn: discRect).fill()
    ctx.restoreGState()

    // Grooves: thin concentric rings from the label edge to the rim.
    let c = NSPoint(x: r.midX, y: r.midY)
    let labelR = discRect.width * 0.30
    let maxR = discRect.width / 2 - s * 0.012
    var gr = labelR + s * 0.02
    while gr < maxR {
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2))
        ring.lineWidth = max(s * 0.0035, 0.5)
        NSColor(white: 0.17, alpha: 1).setStroke()
        ring.stroke()
        gr += s * 0.016
    }

    // Sheen: two soft light wedges across the grooves.
    ctx.saveGState()
    NSBezierPath(ovalIn: discRect).addClip()
    let sheen = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0), 0), (NSColor.white.withAlphaComponent(0.07), 0.18),
        (NSColor.white.withAlphaComponent(0), 0.36), (NSColor.white.withAlphaComponent(0), 0.6),
        (NSColor.white.withAlphaComponent(0.05), 0.78), (NSColor.white.withAlphaComponent(0), 1))!
    sheen.draw(in: discRect, angle: 55)
    ctx.restoreGState()

    // Label: the amber the menu bar icon uses when the collection is open.
    let label = NSRect(x: c.x - labelR, y: c.y - labelR, width: labelR * 2, height: labelR * 2)
    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.40, alpha: 1),
                        NSColor(calibratedRed: 0.93, green: 0.60, blue: 0.22, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: label), angle: -70)
    let labelRing = NSBezierPath(ovalIn: label)
    labelRing.lineWidth = s * 0.006
    NSColor.black.withAlphaComponent(0.55).setStroke()
    labelRing.stroke()
    // A single cut groove on the label, like the corner mark on the card.
    let mark = NSBezierPath(ovalIn: label.insetBy(dx: labelR * 0.22, dy: labelR * 0.22))
    mark.lineWidth = s * 0.004
    NSColor.black.withAlphaComponent(0.18).setStroke()
    mark.stroke()
    // Spindle hole.
    let hole = s * 0.028
    NSColor(white: 0.07, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - hole, y: c.y - hole, width: hole * 2, height: hole * 2)).fill()

    img.unlockFocus()
    return img
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let iconset = out.appendingPathComponent("Cuts.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(draw(size: CGFloat(px)), pixels: px).write(to: iconset.appendingPathComponent(name))
    }
}
try png(draw(size: 512), pixels: 512).write(to: out.appendingPathComponent("icon/preview-512.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("Cuts.icns").path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "wrote \(out.path)/Cuts.icns" : "iconutil failed")
