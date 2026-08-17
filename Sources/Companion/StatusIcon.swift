import AppKit

/// The menu bar mark: the Companion "C" with its live dot, drawn rather than
/// shipped as an asset so it stays crisp at any menu bar size.
///
/// Marked as a template image, which is what lets macOS tint it correctly in
/// light and dark menu bars without shipping two files.
enum StatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)
            let radius = size * 0.29
            let lineWidth = size * 0.18

            let arc = NSBezierPath()
            // Open on the right, like the logo: sweep the long way round from
            // the lower right, over the top, to the upper right.
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 50,
                endAngle: 310,
                clockwise: false
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            let dotRadius = lineWidth * 0.46
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x + radius - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            NSColor.black.setFill()
            dot.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
