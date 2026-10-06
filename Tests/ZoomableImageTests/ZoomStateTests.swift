import CoreGraphics
import Testing
@testable import ZoomableImage

@Suite("Zoom state")
struct ZoomStateTests {
    /// A 4:3 landscape image fitted into a 400 × 800 portrait viewport: 400 × 300 at scale 1.
    let state = ZoomState(
        contentSize: CGSize(width: 400, height: 300),
        viewportSize: CGSize(width: 400, height: 800)
    )

    // MARK: Scale

    @Test func startsAtTheMinimumScaleCentered() {
        #expect(state.scale == 1)
        #expect(state.offset == .zero)
        #expect(!state.isZoomed)
    }

    @Test func clampsTheScale() {
        #expect(state.clampedScale(10) == 4)
        #expect(state.clampedScale(0.2) == 1)
        #expect(state.clampedScale(2.5) == 2.5)
    }

    @Test func rubberBandedScaleIsUnchangedWithinTheLimits() {
        #expect(state.rubberBandedScale(1) == 1)
        #expect(state.rubberBandedScale(2.2) == 2.2)
        #expect(state.rubberBandedScale(4) == 4)
    }

    @Test func rubberBandedScaleResistsAboveTheMaximum() {
        let banded = state.rubberBandedScale(6)
        #expect(banded > 4)
        #expect(banded < 4 * 1.35)
        #expect(state.rubberBandedScale(8) > banded)
        #expect(state.rubberBandedScale(1_000) < 4 * 1.35)
    }

    @Test func rubberBandedScaleResistsBelowTheMinimum() {
        let banded = state.rubberBandedScale(0.5)
        #expect(banded < 1)
        #expect(banded > 1 / 1.35)
        #expect(state.rubberBandedScale(0.2) < banded)
        #expect(state.rubberBandedScale(0.0001) > 1 / 1.35)
    }

    @Test func rubberBandedScaleIsContinuousAtTheLimits() {
        #expect(isClose(state.rubberBandedScale(4.0001), 4, tolerance: 1e-3))
        #expect(isClose(state.rubberBandedScale(0.9999), 1, tolerance: 1e-3))
    }

    @Test func noOvershootClampsInstead() {
        var configuration = ZoomConfiguration()
        configuration.scaleOvershoot = 0
        let strict = ZoomState(contentSize: state.contentSize, viewportSize: state.viewportSize, configuration: configuration)
        #expect(strict.rubberBandedScale(6) == 4)
    }

    // MARK: Anchor-preserving zoom

    @Test func zoomKeepsTheAnchoredPointInPlace() {
        let anchor = CGPoint(x: 300, y: 500)
        let before = state.contentPoint(at: anchor)
        let zoomed = state.zoomed(to: 3, anchor: anchor)
        #expect(zoomed.scale == 3)
        #expect(isClose(zoomed.contentPoint(at: anchor), before))
    }

    @Test func zoomKeepsTheAnchorFromAnAlreadyZoomedState() {
        let start = state.zoomed(to: 2, anchor: CGPoint(x: 100, y: 300))
        let anchor = CGPoint(x: 250, y: 420)
        let before = start.contentPoint(at: anchor)
        let zoomed = start.zoomed(to: 3.5, anchor: anchor)
        #expect(isClose(zoomed.contentPoint(at: anchor), before))
    }

    @Test func zoomAroundTheCenterKeepsTheContentCentered() {
        let zoomed = state.zoomed(to: 3, anchor: state.viewportCenter)
        #expect(isClose(zoomed.offset, .zero))
    }

    @Test func contentAndViewportPointsRoundTrip() {
        let zoomed = state.zoomed(to: 2.7, anchor: CGPoint(x: 80, y: 610))
        let unit = CGPoint(x: 0.31, y: 0.77)
        let onScreen = zoomed.viewportPoint(forContentPoint: unit)
        #expect(isClose(zoomed.contentPoint(at: onScreen), unit))
    }

    // MARK: Pan bounds

    @Test func cannotPanContentThatFitsTheViewport() {
        #expect(state.maximumOffset() == .zero)
        #expect(state.clampedOffset(CGSize(width: 50, height: -80)) == .zero)
    }

    @Test func panBoundsKeepTheEdgesOutsideTheViewport() {
        // At 2x the image is 800 × 600: 200 points to spare on each side, none vertically.
        #expect(state.maximumOffset(at: 2) == CGSize(width: 200, height: 0))
        // At 4x it is 1600 × 1200.
        #expect(state.maximumOffset(at: 4) == CGSize(width: 600, height: 200))
        let clamped = state.clampedOffset(CGSize(width: -900, height: 450), at: 4)
        #expect(clamped == CGSize(width: -600, height: 200))
    }

    @Test func clampedEdgesLineUpWithTheViewport() {
        let zoomed = state.zoomed(to: 4, anchor: state.viewportCenter)
        var pannedFar = zoomed
        pannedFar.offset = zoomed.clampedOffset(CGSize(width: 10_000, height: 10_000))
        // The image's top-left corner sits exactly at the viewport's top-left corner.
        #expect(isClose(pannedFar.viewportPoint(forContentPoint: .zero), .zero))
    }

    @Test func rubberBandedOffsetResistsPastTheEdges() {
        let banded = state.rubberBandedOffset(CGSize(width: 400, height: 50), at: 2.5)
        // 300 points to spare horizontally at 2.5x, none vertically.
        #expect(banded.width > 300)
        #expect(banded.width < 400)
        #expect(banded.height > 0)
        #expect(banded.height < 50)
    }

    @Test func rubberBandedOffsetIsUnchangedWithinTheBounds() {
        let offset = CGSize(width: -120, height: 0)
        #expect(state.rubberBandedOffset(offset, at: 2.5) == offset)
    }

    @Test func hardEdgesClampInsteadOfRubberBanding() {
        var configuration = ZoomConfiguration()
        configuration.rubberBandsEdges = false
        let strict = ZoomState(contentSize: state.contentSize, viewportSize: state.viewportSize, configuration: configuration, scale: 2.5)
        #expect(strict.rubberBandedOffset(CGSize(width: 400, height: 50)) == CGSize(width: 300, height: 0))
    }

    @Test func panMovesFromTheStartOffset() {
        let zoomed = ZoomState(contentSize: state.contentSize, viewportSize: state.viewportSize, scale: 2.5)
        let panned = zoomed.panned(from: CGSize(width: -50, height: 0), by: CGSize(width: 100, height: 0))
        #expect(panned.offset == CGSize(width: 50, height: 0))
    }

    // MARK: Settling

    @Test func settlingClampsAnOverZoomAroundTheAnchor() {
        let anchor = CGPoint(x: 300, y: 500)
        let overZoomed = state.zoomed(to: 6, anchor: anchor)
        let settled = overZoomed.settled(anchor: anchor)
        #expect(settled.scale == 4)
        let bound = settled.maximumOffset()
        #expect(abs(settled.offset.width) <= bound.width)
        #expect(abs(settled.offset.height) <= bound.height)
    }

    @Test func settlingAnUnderZoomRecenters() {
        let underZoomed = state.zoomed(to: 0.6, anchor: CGPoint(x: 10, y: 10))
        let settled = underZoomed.settled()
        #expect(settled.scale == 1)
        #expect(isClose(settled.offset, .zero))
    }

    @Test func settlingLeavesAValidStateAlone() {
        let valid = ZoomState(contentSize: state.contentSize, viewportSize: state.viewportSize, scale: 2, offset: CGSize(width: 150, height: 0))
        #expect(valid.settled() == valid)
    }

    // MARK: Double tap

    @Test func doubleTapZoomsInAroundTheTappedPoint() {
        let tap = CGPoint(x: 350, y: 400)
        let target = state.doubleTapTarget(at: tap)
        #expect(target.scale == 2.5)
        #expect(isClose(target.offset, CGSize(width: -225, height: 0)))
        #expect(isClose(target.contentPoint(at: tap), state.contentPoint(at: tap)))
    }

    @Test func doubleTapOnTheCenterStaysCentered() {
        let target = state.doubleTapTarget(at: state.viewportCenter)
        #expect(target.scale == 2.5)
        #expect(isClose(target.offset, .zero))
    }

    @Test func doubleTapNearAnEdgeKeepsTheImageInside() {
        let target = state.doubleTapTarget(at: CGPoint(x: 395, y: 700))
        let bound = target.maximumOffset()
        #expect(abs(target.offset.width) <= bound.width)
        #expect(target.offset.height == 0)
    }

    @Test func doubleTapWhenZoomedResets() {
        let zoomed = state.doubleTapTarget(at: CGPoint(x: 120, y: 380))
        let reset = zoomed.doubleTapTarget(at: CGPoint(x: 10, y: 10))
        #expect(reset.scale == 1)
        #expect(reset.offset == .zero)
    }

    @Test func doubleTapScaleIsClamped() {
        var configuration = ZoomConfiguration()
        configuration.doubleTapScale = 9
        let custom = ZoomState(contentSize: state.contentSize, viewportSize: state.viewportSize, configuration: configuration)
        let target = custom.doubleTapTarget(at: custom.viewportCenter)
        #expect(target.scale == 4)
    }

    // MARK: Initial zoom

    @Test func zoomCentersOnAContentPoint() {
        let target = state.zoomed(to: ZoomTarget(scale: 2.5, anchor: CGPoint(x: 0.75, y: 0.5)))
        #expect(isClose(target.offset, CGSize(width: -250, height: 0)))
        #expect(isClose(target.viewportPoint(forContentPoint: CGPoint(x: 0.75, y: 0.5)), target.viewportCenter))
    }

    @Test func zoomOnACornerStopsAtTheEdges() {
        let target = state.zoomed(to: 2.5, centeredOn: CGPoint(x: 1, y: 1))
        #expect(target.offset == CGSize(width: -300, height: 0))
    }

    @Test func fillScaleCoversTheViewport() {
        #expect(isClose(state.fillScale, 800.0 / 300.0))
        let filled = ZoomState(contentSize: CGSize(width: 1067, height: 800), viewportSize: CGSize(width: 400, height: 800))
        #expect(filled.fillScale == 1)
    }

    @Test func filledContentCanBePannedAtTheMinimumScale() {
        let filled = ZoomState(contentSize: CGSize(width: 1067, height: 800), viewportSize: CGSize(width: 400, height: 800))
        #expect(!filled.isZoomed)
        #expect(isClose(filled.maximumOffset().width, 333.5))
        #expect(filled.maximumOffset().height == 0)
    }
}
