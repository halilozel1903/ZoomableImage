import CoreGraphics
import Testing
@testable import ZoomableImage

@Suite("Swipe to dismiss")
struct DismissStateTests {
    @Test func progressFollowsTheDistance() {
        let state = DismissState(translation: CGSize(width: 12, height: 160))
        #expect(isClose(state.progress, 0.5))
        #expect(isClose(CGFloat(state.backgroundOpacity), 0.5))
        #expect(isClose(state.contentScale, 0.85))
    }

    @Test func progressStopsAtOne() {
        let state = DismissState(translation: CGSize(width: 0, height: 1_000))
        #expect(state.progress == 1)
        #expect(state.backgroundOpacity == 0)
        #expect(isClose(state.contentScale, 0.7))
    }

    @Test func atRestNothingChanges() {
        let state = DismissState()
        #expect(state.progress == 0)
        #expect(state.backgroundOpacity == 1)
        #expect(state.contentScale == 1)
        #expect(state.contentOffset == .zero)
    }

    @Test func pullingUpRubberBandsWithoutProgress() {
        let state = DismissState(translation: CGSize(width: 0, height: -200))
        #expect(state.progress == 0)
        #expect(state.contentOffset.height < 0)
        #expect(state.contentOffset.height > -200)
    }

    @Test func upwardSwipesCountWhenAllowed() {
        var configuration = DismissConfiguration()
        configuration.allowsUpwardSwipe = true
        let state = DismissState(translation: CGSize(width: 0, height: -160), configuration: configuration)
        #expect(isClose(state.progress, 0.5))
        #expect(state.contentOffset.height == -160)
        #expect(state.shouldDismiss(velocity: CGSize(width: 0, height: -300)))
    }

    @Test func dismissesPastTheDistanceThreshold() {
        let state = DismissState(translation: CGSize(width: 0, height: 130))
        #expect(state.shouldDismiss(velocity: .zero))
    }

    @Test func dismissesAFastShortFlick() {
        let state = DismissState(translation: CGSize(width: 0, height: 60))
        #expect(state.shouldDismiss(velocity: CGSize(width: 0, height: 1_000)))
        #expect(!state.shouldDismiss(velocity: CGSize(width: 0, height: 100)))
    }

    @Test func ignoresATinyFlick() {
        let state = DismissState(translation: CGSize(width: 0, height: 10))
        #expect(!state.shouldDismiss(velocity: CGSize(width: 0, height: 3_000)))
    }

    @Test func flickingBackCancels() {
        let state = DismissState(translation: CGSize(width: 0, height: 200))
        #expect(!state.shouldDismiss(velocity: CGSize(width: 0, height: -600)))
    }

    @Test func upwardSwipeDoesNotDismissByDefault() {
        let state = DismissState(translation: CGSize(width: 0, height: -200))
        #expect(!state.shouldDismiss(velocity: CGSize(width: 0, height: -1_000)))
    }

    @Test func disabledNeverDismisses() {
        let state = DismissState(translation: CGSize(width: 0, height: 400), configuration: DismissConfiguration(isEnabled: false))
        #expect(!state.shouldDismiss(velocity: CGSize(width: 0, height: 2_000)))
    }

    @Test func dismissDragsAreMostlyVerticalAndDownward() {
        #expect(DismissState.isDismissDrag(translation: CGSize(width: 2, height: 10)))
        #expect(!DismissState.isDismissDrag(translation: CGSize(width: 10, height: 2)))
        #expect(!DismissState.isDismissDrag(translation: CGSize(width: 0, height: -10)))
        #expect(!DismissState.isDismissDrag(translation: .zero))
        var upward = DismissConfiguration()
        upward.allowsUpwardSwipe = true
        #expect(DismissState.isDismissDrag(translation: CGSize(width: 0, height: -10), configuration: upward))
        #expect(!DismissState.isDismissDrag(translation: CGSize(width: 0, height: 10), configuration: DismissConfiguration(isEnabled: false)))
    }

    @Test func configurationCorrectsInvalidValues() {
        let configuration = DismissConfiguration(distanceThreshold: -5, fadeDistance: 0, minimumContentScale: 3)
        #expect(configuration.distanceThreshold == 0)
        #expect(configuration.fadeDistance == 1)
        #expect(configuration.minimumContentScale == 1)
    }
}

@Suite("Gallery paging")
struct GalleryPagingTests {
    @Test func swipingFarEnoughMovesOnePage() {
        #expect(GalleryPaging.targetIndex(current: 2, count: 5, predictedEndTranslation: -250, pageWidth: 400) == 3)
        #expect(GalleryPaging.targetIndex(current: 2, count: 5, predictedEndTranslation: 250, pageWidth: 400) == 1)
    }

    @Test func aShortSwipeStays() {
        #expect(GalleryPaging.targetIndex(current: 2, count: 5, predictedEndTranslation: -100, pageWidth: 400) == 2)
        #expect(GalleryPaging.targetIndex(current: 2, count: 5, predictedEndTranslation: 199, pageWidth: 400) == 2)
    }

    @Test func aLongFlickStillMovesOnlyOnePage() {
        #expect(GalleryPaging.targetIndex(current: 1, count: 5, predictedEndTranslation: -3_000, pageWidth: 400) == 2)
    }

    @Test func staysWithinTheFirstAndLastPage() {
        #expect(GalleryPaging.targetIndex(current: 4, count: 5, predictedEndTranslation: -500, pageWidth: 400) == 4)
        #expect(GalleryPaging.targetIndex(current: 0, count: 5, predictedEndTranslation: 500, pageWidth: 400) == 0)
        #expect(GalleryPaging.targetIndex(current: 9, count: 5, predictedEndTranslation: 0, pageWidth: 400) == 4)
    }

    @Test func handlesEmptyGalleriesAndZeroWidths() {
        #expect(GalleryPaging.targetIndex(current: 0, count: 0, predictedEndTranslation: -500, pageWidth: 400) == 0)
        #expect(GalleryPaging.targetIndex(current: 1, count: 3, predictedEndTranslation: -500, pageWidth: 0) == 1)
    }

    @Test func pagesFollowTheFingerInTheMiddle() {
        #expect(GalleryPaging.offset(for: -120, current: 2, count: 5, pageWidth: 400) == -120)
        #expect(GalleryPaging.offset(for: 120, current: 2, count: 5, pageWidth: 400) == 120)
    }

    @Test func pagesRubberBandPastTheEnds() {
        let first = GalleryPaging.offset(for: 120, current: 0, count: 5, pageWidth: 400)
        #expect(first > 0 && first < 120)
        let last = GalleryPaging.offset(for: -120, current: 4, count: 5, pageWidth: 400)
        #expect(last < 0 && last > -120)
        // Moving away from the end is not resisted.
        #expect(GalleryPaging.offset(for: 120, current: 4, count: 5, pageWidth: 400) == 120)
    }

    @Test func stripOffsetIncludesTheSpacing() {
        #expect(GalleryPaging.stripOffset(index: 2, pageWidth: 400, spacing: 16) == -832)
        #expect(GalleryPaging.stripOffset(index: 0, pageWidth: 400, spacing: 16) == 0)
    }
}
