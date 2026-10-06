import CoreGraphics
import Foundation

/// Geometry helpers shared by the zoom, pan, dismiss and paging math.
///
/// Everything here is pure: no views, no state, no animation. The views feed gesture values in and
/// draw what comes out, so the behavior is covered by unit tests.
public enum ZoomMath {
    /// The size of content with the aspect ratio of `aspect` scaled to fit inside `bounds`
    /// (letterboxed, like `.scaledToFit()`).
    public static func fitSize(for aspect: CGSize, in bounds: CGSize) -> CGSize {
        guard aspect.width > 0, aspect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let factor = min(bounds.width / aspect.width, bounds.height / aspect.height)
        return CGSize(width: aspect.width * factor, height: aspect.height * factor)
    }

    /// The size of content with the aspect ratio of `aspect` scaled to cover `bounds` completely
    /// (cropped, like `.scaledToFill()`).
    public static func fillSize(for aspect: CGSize, in bounds: CGSize) -> CGSize {
        guard aspect.width > 0, aspect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let factor = max(bounds.width / aspect.width, bounds.height / aspect.height)
        return CGSize(width: aspect.width * factor, height: aspect.height * factor)
    }

    /// The size of `aspect` fitted or filled into `bounds`.
    public static func size(for aspect: CGSize, in bounds: CGSize, mode: ZoomContentMode) -> CGSize {
        switch mode {
        case .fit: fitSize(for: aspect, in: bounds)
        case .fill: fillSize(for: aspect, in: bounds)
        }
    }

    /// How far content moves when it is pulled `overshoot` points past a limit, the way a
    /// `UIScrollView` resists: `(1 - 1 / (overshoot × coefficient / dimension + 1)) × dimension`.
    ///
    /// The result follows the finger at first (its slope at zero is `coefficient`), grows more and
    /// more slowly and never reaches `dimension`. Negative overshoots mirror positive ones.
    public static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0, coefficient > 0, overshoot != 0 else { return 0 }
        let magnitude = abs(overshoot)
        let banded = (1 - 1 / (magnitude * coefficient / dimension + 1)) * dimension
        return overshoot < 0 ? -banded : banded
    }

    /// `value` limited to `range`.
    public static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// How content is sized at the minimum zoom scale.
public enum ZoomContentMode: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The whole image is visible, with bars on two sides when the aspect ratios differ.
    case fit
    /// The image covers the viewport; the overflow can be panned into view.
    case fill
}
