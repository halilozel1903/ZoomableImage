import CoreGraphics
import Foundation

/// The paging math of ``ImageGallery``: which page a swipe lands on and how the pages follow the
/// finger.
public enum GalleryPaging {
    /// The page a horizontal swipe ends on.
    ///
    /// - Parameters:
    ///   - current: The page the swipe started on.
    ///   - count: The number of pages.
    ///   - predictedEndTranslation: Where the drag would stop with its current velocity
    ///     (`DragGesture.Value.predictedEndTranslation.width`). Negative values move forward.
    ///   - pageWidth: The width of one page.
    ///   - threshold: The fraction of a page the predicted translation must cover to change pages.
    /// - Returns: `current`, or the next or previous page, never outside `0..<count`.
    public static func targetIndex(
        current: Int,
        count: Int,
        predictedEndTranslation: CGFloat,
        pageWidth: CGFloat,
        threshold: CGFloat = 0.5
    ) -> Int {
        guard count > 0 else { return 0 }
        let current = min(max(current, 0), count - 1)
        guard pageWidth > 0 else { return current }
        var target = current
        if predictedEndTranslation <= -pageWidth * threshold {
            target = current + 1
        } else if predictedEndTranslation >= pageWidth * threshold {
            target = current - 1
        }
        return min(max(target, 0), count - 1)
    }

    /// How far the pages move for a drag `translation`: one to one, except past the first and the
    /// last page, where they rubber-band.
    public static func offset(for translation: CGFloat, current: Int, count: Int, pageWidth: CGFloat) -> CGFloat {
        let pullsPastStart = current <= 0 && translation > 0
        let pullsPastEnd = current >= count - 1 && translation < 0
        if pullsPastStart || pullsPastEnd {
            return ZoomMath.rubberBand(translation, dimension: pageWidth)
        }
        return translation
    }

    /// The horizontal offset of the strip of pages that shows page `index`.
    public static func stripOffset(index: Int, pageWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        -CGFloat(index) * (pageWidth + spacing)
    }
}
