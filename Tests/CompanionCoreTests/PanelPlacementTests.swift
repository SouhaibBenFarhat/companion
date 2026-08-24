import XCTest
@testable import CompanionCore

final class PanelPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testLeavesAFrameThatAlreadyFits() {
        let frame = CGRect(x: 200, y: 200, width: 460, height: 560)
        XCTAssertEqual(PanelPlacement.clamp(frame: frame, into: screen), frame)
    }

    func testPullsBackAFrameOffTheRightEdge() {
        let frame = CGRect(x: 1400, y: 200, width: 460, height: 560)
        let clamped = PanelPlacement.clamp(frame: frame, into: screen)
        XCTAssertEqual(clamped.maxX, screen.maxX - PanelPlacement.margin)
        XCTAssertEqual(clamped.size, frame.size)
    }

    func testPullsBackAFrameOffTheBottomEdge() {
        let frame = CGRect(x: 200, y: -400, width: 460, height: 560)
        let clamped = PanelPlacement.clamp(frame: frame, into: screen)
        XCTAssertEqual(clamped.minY, screen.minY + PanelPlacement.margin)
    }

    /// The real case this guards: a position saved on a large monitor that is
    /// no longer plugged in.
    func testBringsBackAFrameSavedOnAMonitorThatIsGone() {
        let frame = CGRect(x: 3000, y: 1600, width: 460, height: 560)
        let clamped = PanelPlacement.clamp(frame: frame, into: screen)
        XCTAssertTrue(screen.contains(clamped), "\(clamped) should sit inside \(screen)")
    }

    func testShrinksAPanelTallerThanTheScreen() {
        let frame = CGRect(x: 0, y: 0, width: 460, height: 2000)
        let clamped = PanelPlacement.clamp(frame: frame, into: screen)
        XCTAssertLessThanOrEqual(clamped.height, screen.height)
        XCTAssertTrue(screen.contains(clamped))
    }

    func testShrinksAPanelWiderThanTheScreen() {
        let frame = CGRect(x: 0, y: 0, width: 3000, height: 400)
        let clamped = PanelPlacement.clamp(frame: frame, into: screen)
        XCTAssertLessThanOrEqual(clamped.width, screen.width)
        XCTAssertTrue(screen.contains(clamped))
    }

    /// A second display sits at a non-zero origin; clamping must respect it
    /// rather than assuming the screen starts at 0,0.
    func testRespectsAScreenWithANonZeroOrigin() {
        let secondary = CGRect(x: 1440, y: 300, width: 1280, height: 800)
        let frame = CGRect(x: 0, y: 0, width: 460, height: 560)
        let clamped = PanelPlacement.clamp(frame: frame, into: secondary)
        XCTAssertTrue(secondary.contains(clamped))
        XCTAssertEqual(clamped.minX, secondary.minX + PanelPlacement.margin)
    }

    func testSurvivesAScreenSmallerThanTheMargins() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        let clamped = PanelPlacement.clamp(frame: CGRect(x: 5, y: 5, width: 460, height: 560), into: tiny)
        XCTAssertGreaterThanOrEqual(clamped.width, 0)
        XCTAssertGreaterThanOrEqual(clamped.height, 0)
        XCTAssertFalse(clamped.width.isNaN)
        XCTAssertFalse(clamped.height.isNaN)
    }

    func testDefaultFrameSitsOnTheRightAndIsVerticallyCentred() {
        let size = CGSize(width: 460, height: 560)
        let frame = PanelPlacement.defaultFrame(size: size, in: screen)
        XCTAssertEqual(frame.maxX, screen.maxX - PanelPlacement.margin)
        XCTAssertEqual(frame.midY, screen.midY, accuracy: 0.5)
        XCTAssertTrue(screen.contains(frame))
    }

    func testDefaultFrameStaysOnScreenWhenThePanelIsHuge() {
        let frame = PanelPlacement.defaultFrame(size: CGSize(width: 4000, height: 4000), in: screen)
        XCTAssertTrue(screen.contains(frame))
    }

    // MARK: - Carried from a large display to a small one

    /// The reported bug. A panel sized on a 6K monitor, reopened on a laptop:
    /// wider and taller than the screen, so its edges and its drag strip were
    /// both off the display. It could not be resized and it could not be moved.
    func testShrinksAPanelCarriedFromALargerDisplay() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 895)
        let oversized = CGRect(x: 40, y: -300, width: 2200, height: 1400)

        let clamped = PanelPlacement.clamp(frame: oversized, into: laptop)

        XCTAssertLessThanOrEqual(clamped.width, laptop.width)
        XCTAssertLessThanOrEqual(clamped.height, laptop.height)
        XCTAssertTrue(laptop.contains(clamped), "the whole panel has to be reachable")
    }

    /// Every edge has to be inside the screen, or that edge cannot be dragged
    /// to resize the window.
    func testEveryEdgeStaysGrabbable() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 895)
        for frame in [
            CGRect(x: -900, y: -900, width: 3000, height: 2000),
            CGRect(x: 1400, y: 800, width: 800, height: 900),
            CGRect(x: 0, y: 0, width: 1512, height: 895),
        ] {
            let clamped = PanelPlacement.clamp(frame: frame, into: laptop)
            XCTAssertGreaterThanOrEqual(clamped.minX, laptop.minX, "\(frame)")
            XCTAssertGreaterThanOrEqual(clamped.minY, laptop.minY, "\(frame)")
            XCTAssertLessThanOrEqual(clamped.maxX, laptop.maxX, "\(frame)")
            XCTAssertLessThanOrEqual(clamped.maxY, laptop.maxY, "\(frame)")
        }
    }

    // MARK: - Choosing the display

    private let left = CGRect(x: 0, y: 0, width: 1512, height: 895)
    private let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    func testPicksTheDisplayThePanelSitsOn() {
        let onTheRight = CGRect(x: 2000, y: 300, width: 460, height: 560)
        XCTAssertEqual(PanelPlacement.target(for: onTheRight, among: [left, right]), right)
    }

    /// Straddling two displays goes to whichever holds more of the panel, the
    /// same rule AppKit uses.
    func testPicksTheDisplayHoldingMostOfThePanel() {
        let mostlyLeft = CGRect(x: 1200, y: 300, width: 400, height: 560)
        XCTAssertEqual(PanelPlacement.target(for: mostlyLeft, among: [left, right]), left)

        let mostlyRight = CGRect(x: 1450, y: 300, width: 400, height: 560)
        XCTAssertEqual(PanelPlacement.target(for: mostlyRight, among: [left, right]), right)
    }

    /// The monitor it was saved on has been unplugged, so it overlaps nothing.
    func testFallsBackWhenTheSavedDisplayIsGone() {
        let ghost = CGRect(x: 4000, y: 2000, width: 460, height: 560)
        XCTAssertEqual(PanelPlacement.target(for: ghost, among: [left]), left)
    }

    func testTargetIsNilWithNoDisplays() {
        XCTAssertNil(PanelPlacement.target(for: .zero, among: []))
    }
}
