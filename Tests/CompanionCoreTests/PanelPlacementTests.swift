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
}
