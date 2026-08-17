import CoreGraphics
import Foundation

/// Where the panel sits on screen.
///
/// Kept free of AppKit so the arithmetic can be tested without a display —
/// the awkward cases (a saved position on a monitor you unplugged, a panel
/// taller than the screen) are exactly the ones you cannot reproduce by hand.
public enum PanelPlacement {
    public static let margin: CGFloat = 12

    /// Pulls a frame back inside the visible area.
    ///
    /// If the panel is larger than the screen it is shrunk to fit rather than
    /// pushed off an edge — a panel with its input box below the dock is
    /// useless, and that is what unplugging a large monitor produces.
    public static func clamp(
        frame: CGRect,
        into visible: CGRect,
        margin: CGFloat = margin
    ) -> CGRect {
        let maxWidth = max(0, visible.width - margin * 2)
        let maxHeight = max(0, visible.height - margin * 2)
        let size = CGSize(
            width: min(frame.width, maxWidth),
            height: min(frame.height, maxHeight)
        )

        let minX = visible.minX + margin
        let maxX = visible.maxX - margin - size.width
        let minY = visible.minY + margin
        let maxY = visible.maxY - margin - size.height

        // When the screen is narrower than the margins allow, minX can exceed
        // maxX; pinning to minX keeps the panel on screen instead of inverting.
        let x = maxX >= minX ? min(max(frame.minX, minX), maxX) : minX
        let y = maxY >= minY ? min(max(frame.minY, minY), maxY) : minY

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Default position for a first launch: right-hand side, vertically centred.
    /// Out of the way of the content you are presenting, which tends to sit left.
    public static func defaultFrame(size: CGSize, in visible: CGRect, margin: CGFloat = margin) -> CGRect {
        let frame = CGRect(
            x: visible.maxX - margin - size.width,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return clamp(frame: frame, into: visible, margin: margin)
    }
}
