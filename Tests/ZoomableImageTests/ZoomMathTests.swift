import CoreGraphics
import Testing
@testable import ZoomableImage

@Suite("Fit, fill and rubber-banding")
struct ZoomMathTests {
    let phone = CGSize(width: 390, height: 844)

    @Test func fitsALandscapeImageToTheWidth() {
        let size = ZoomMath.fitSize(for: CGSize(width: 4000, height: 3000), in: phone)
        #expect(isClose(size, CGSize(width: 390, height: 292.5)))
    }

    @Test func fitsAPortraitImageToTheHeight() {
        let size = ZoomMath.fitSize(for: CGSize(width: 1000, height: 4000), in: phone)
        #expect(isClose(size, CGSize(width: 211, height: 844)))
    }

    @Test func fillsTheViewportCompletely() {
        let size = ZoomMath.fillSize(for: CGSize(width: 4000, height: 3000), in: phone)
        #expect(isClose(size.height, 844))
        #expect(isClose(size.width, 844 * 4 / 3))
        #expect(size.width >= phone.width)
    }

    @Test func sizeFollowsTheContentMode() {
        let aspect = CGSize(width: 3, height: 2)
        #expect(ZoomMath.size(for: aspect, in: phone, mode: .fit) == ZoomMath.fitSize(for: aspect, in: phone))
        #expect(ZoomMath.size(for: aspect, in: phone, mode: .fill) == ZoomMath.fillSize(for: aspect, in: phone))
    }

    @Test func emptySizesGiveZero() {
        #expect(ZoomMath.fitSize(for: .zero, in: phone) == .zero)
        #expect(ZoomMath.fillSize(for: CGSize(width: 3, height: 2), in: .zero) == .zero)
    }

    @Test func rubberBandStartsAtZeroAndFollowsTheCoefficient() {
        #expect(ZoomMath.rubberBand(0, dimension: 400) == 0)
        let tiny = ZoomMath.rubberBand(0.01, dimension: 400)
        #expect(isClose(tiny, 0.0055, tolerance: 1e-5))
    }

    @Test func rubberBandMatchesTheFormula() {
        let value = ZoomMath.rubberBand(100, dimension: 400, coefficient: 0.55)
        let expected = (1 - 1 / (100 * 0.55 / 400 + 1)) * 400
        #expect(isClose(value, expected))
        #expect(value < 100 * 0.55)
    }

    @Test func rubberBandNeverReachesTheDimension() {
        let far = ZoomMath.rubberBand(1_000_000, dimension: 400)
        #expect(far < 400)
        #expect(far > 390)
    }

    @Test func rubberBandIsSymmetric() {
        let down = ZoomMath.rubberBand(-120, dimension: 400)
        let up = ZoomMath.rubberBand(120, dimension: 400)
        #expect(isClose(down, -up))
    }

    @Test func rubberBandGrowsMonotonically() {
        var previous: CGFloat = 0
        for overshoot in stride(from: CGFloat(10), through: 1000, by: 10) {
            let value = ZoomMath.rubberBand(overshoot, dimension: 300)
            #expect(value > previous)
            previous = value
        }
    }

    @Test func clampLimitsToTheRange() {
        #expect(ZoomMath.clamp(5, to: 1...4) == 4)
        #expect(ZoomMath.clamp(0.5, to: 1...4) == 1)
        #expect(ZoomMath.clamp(2, to: 1...4) == 2)
    }

    @Test func configurationCorrectsInvalidLimits() {
        let inverted = ZoomConfiguration(minimumScale: 3, maximumScale: 2)
        #expect(inverted.scaleRange == 3...3)
        let zero = ZoomConfiguration(minimumScale: 0, maximumScale: 4)
        #expect(zero.scaleRange == 0.1...4)
        let negativeOvershoot = ZoomConfiguration(scaleOvershoot: -1)
        #expect(negativeOvershoot.scaleOvershoot == 0)
    }
}
