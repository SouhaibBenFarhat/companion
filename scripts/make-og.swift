// Generates site/og.png — the social preview card for the landing page.
// Run:  swift scripts/make-og.swift
// Same two flat shapes as the app icon, next to the name and one line of copy.

import AppKit

let width = 1200
let height = 630
let workDir = FileManager.default.currentDirectoryPath
let output = "\(workDir)/site/og.png"

let background = NSColor(srgbRed: 0.082, green: 0.086, blue: 0.110, alpha: 1) // #15161C
let markColour = NSColor(srgbRed: 0.424, green: 0.388, blue: 1.000, alpha: 1) // #6C63FF
let muted = NSColor(srgbRed: 0.62, green: 0.63, blue: 0.70, alpha: 1)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

background.setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))).fill()

// The mark, left of the text.
let markCentre = CGPoint(x: 232, y: CGFloat(height) / 2)
let radius: CGFloat = 96
let stroke: CGFloat = 44

markColour.setStroke()
let arc = NSBezierPath()
arc.appendArc(withCenter: markCentre, radius: radius, startAngle: 50, endAngle: 310, clockwise: false)
arc.lineWidth = stroke
arc.lineCapStyle = .round
arc.stroke()

markColour.setFill()
let dotRadius = stroke * 0.5
NSBezierPath(ovalIn: CGRect(
    x: markCentre.x + radius * 0.976 - dotRadius,
    y: markCentre.y - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
)).fill()

func draw(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, colour: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: colour,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}

draw("Companion", at: CGPoint(x: 392, y: 342), size: 82, weight: .semibold, colour: .white)
draw("A chat panel for macOS that never appears", at: CGPoint(x: 396, y: 268), size: 34, weight: .regular, colour: muted)
draw("in screen share.", at: CGPoint(x: 396, y: 218), size: 34, weight: .regular, colour: muted)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png data") }
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
