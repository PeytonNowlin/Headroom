#!/usr/bin/swift
// Renders the Headroom app icon (a notch with a draining ring beneath it) to Headroom.icns.
// Usage: swift script/make-icon.swift script/Headroom.icns
import AppKit

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = size
    let inset = s * 0.10  // macOS icons sit inside a ~10% margin
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.2237

    // Tile: near-black with a subtle top-to-bottom gradient.
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [CGColor(gray: 0.16, alpha: 1), CGColor(gray: 0.06, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // Notch: a flared black bar hanging from the top edge.
    let notchWidth = tile.width * 0.46
    let notchHeight = tile.height * 0.12
    let flare = notchHeight * 0.9
    let nx = tile.midX - notchWidth / 2
    let top = tile.maxY
    let bottom = top - notchHeight
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx - flare, y: top))
    notch.addQuadCurve(to: CGPoint(x: nx, y: top - flare), control: CGPoint(x: nx, y: top))
    notch.addLine(to: CGPoint(x: nx, y: bottom + flare))
    notch.addQuadCurve(to: CGPoint(x: nx + flare, y: bottom), control: CGPoint(x: nx, y: bottom))
    notch.addLine(to: CGPoint(x: nx + notchWidth - flare, y: bottom))
    notch.addQuadCurve(to: CGPoint(x: nx + notchWidth, y: bottom + flare), control: CGPoint(x: nx + notchWidth, y: bottom))
    notch.addLine(to: CGPoint(x: nx + notchWidth, y: top - flare))
    notch.addQuadCurve(to: CGPoint(x: nx + notchWidth + flare, y: top), control: CGPoint(x: nx + notchWidth, y: top))
    notch.closeSubpath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(notch)
    ctx.fillPath()

    // Ring: a track with a bright arc showing ~70% remaining.
    let center = CGPoint(x: tile.midX, y: tile.midY - tile.height * 0.08)
    let ringRadius = tile.width * 0.26
    let lineWidth = tile.width * 0.075
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    let start = CGFloat.pi / 2
    let end = start - 2 * .pi * 0.7
    ctx.setStrokeColor(CGColor(srgbRed: 0.30, green: 0.85, blue: 0.50, alpha: 1))
    ctx.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = CommandLine.arguments.dropFirst().first ?? "Headroom.icns"
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Headroom.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(draw(size: CGFloat(pixels)), pixels: pixels).write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
exit(task.terminationStatus)
