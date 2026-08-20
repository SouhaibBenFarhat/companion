import AppKit

/// The menu bar mark: the Companion "C" with its live dot, drawn rather than
/// shipped as an asset so it stays crisp at any menu bar size.
///
/// Marked as a template image, which is what lets macOS tint it correctly in
/// light and dark menu bars without shipping two files.
enum StatusIcon {
    /// The listening variant carries a red dot.
    ///
    /// macOS shows its own recording indicator in the menu bar, and the menu
    /// bar is inside a shared screen — so listening is visible whatever we do.
    /// Being obvious about it is the honest choice, not a cost.
    /// - Parameter development: draws the mark hollow. If a development build
    ///   and an installed one look the same in the menu bar, you eventually
    ///   spend twenty minutes debugging the wrong one.
    static func make(size: CGFloat = 18, listening: Bool = false, development: Bool = false) -> NSImage {
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
            if development {
                // Outlined rather than filled.
                NSColor.black.setStroke()
                dot.lineWidth = lineWidth * 0.3
                dot.stroke()
            } else {
                NSColor.black.setFill()
                dot.fill()
            }

            if listening {
                let radius = size * 0.15
                let indicator = NSBezierPath(ovalIn: NSRect(
                    x: size - radius * 2,
                    y: size - radius * 2,
                    width: radius * 2,
                    height: radius * 2
                ))
                NSColor.systemRed.setFill()
                indicator.fill()
            }

            return true
        }
        // A template image is tinted by the system, which would turn the red
        // dot the same colour as everything else.
        image.isTemplate = !listening
        return image
    }
}
