// Generates packaging/AppIcon.icns.
// Run:  swift scripts/make-icon.swift
// Draws the Companion mark — an open "C" with a live dot in the gap — on a
// near-black tile, writes a 1024px master PNG, then builds the .icns via
// sips + iconutil. Deliberately flat: no gradients, no glows.

import AppKit

let size = 1024
let workDir = FileManager.default.currentDirectoryPath
let packagingDir = "\(workDir)/packaging"
let iconsetDir = "\(packagingDir)/AppIcon.iconset"
let masterPNG = "\(packagingDir)/icon-1024.png"

let tileColour = NSColor(srgbRed: 0.082, green: 0.086, blue: 0.110, alpha: 1) // #15161C
let markColour = NSColor(srgbRed: 0.424, green: 0.388, blue: 1.000, alpha: 1) // #6C63FF

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let s = CGFloat(size)
let center = CGPoint(x: s / 2, y: s / 2)

// Tile: macOS icons float inside the canvas rather than filling it.
let inset: CGFloat = s * 0.06
let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let corner = tile.width * 0.229
tileColour.setFill()
NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner).fill()

// The C: swept the long way round, leaving the gap on the right.
let radius = s * 0.283
let stroke = s * 0.129

markColour.setStroke()
let arc = NSBezierPath()
arc.appendArc(withCenter: center, radius: radius, startAngle: 50, endAngle: 310, clockwise: false)
arc.lineWidth = stroke
arc.lineCapStyle = .round
arc.stroke()

// The dot in the gap. Two flat shapes total, so it still reads at 16px.
markColour.setFill()
let dotRadius = stroke * 0.5
let dotCentre = CGPoint(x: center.x + s * 0.276, y: center.y)
NSBezierPath(ovalIn: CGRect(
    x: dotCentre.x - dotRadius,
    y: dotCentre.y - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png data") }
try png.write(to: URL(fileURLWithPath: masterPNG))
print("wrote \(masterPNG)")

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func run(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("failed: \(args.joined(separator: " "))") }
}

for v in variants {
    run(["sips", "-z", "\(v.px)", "\(v.px)", masterPNG,
         "--out", "\(iconsetDir)/\(v.name).png"])
}
run(["iconutil", "-c", "icns", iconsetDir, "-o", "\(packagingDir)/AppIcon.icns"])
print("wrote \(packagingDir)/AppIcon.icns")

// The landing page uses a smaller copy of the same master.
run(["sips", "-z", "256", "256", masterPNG, "--out", "\(workDir)/site/icon.png"])
print("wrote \(workDir)/site/icon.png")
