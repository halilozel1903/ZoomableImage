import CoreGraphics
import Foundation

/// The zoom scale and pan offset of content in a viewport, and the math that moves them.
///
/// The content is laid out at `contentSize` (its fitted or filled size at scale 1), centered in
/// `viewportSize`, then scaled by `scale` around the viewport's center and moved by `offset`.
/// A point `p` of the content, measured from the content's center, appears at
/// `viewportCenter + offset + scale × p`.
///
/// Every method returns a new state, so gesture handlers stay small and the behavior is easy to
/// test:
///
/// ```swift
/// let state = ZoomState(contentSize: CGSize(width: 390, height: 260), viewportSize: CGSize(width: 390, height: 844))
/// let zoomed = state.zoomed(to: 3, anchor: CGPoint(x: 300, y: 400))   // the point at (300, 400) stays put
/// let settled = zoomed.settled()                                       // scale and offset within limits
/// ```
public struct ZoomState: Equatable, Sendable {
    /// The scale applied to the content. `configuration.minimumScale` shows it at `contentSize`.
    public var scale: CGFloat
    /// The translation of the content's center from the viewport's center, in points.
    public var offset: CGSize
    /// The size of the content at scale 1.
    public var contentSize: CGSize
    /// The size of the visible area.
    public var viewportSize: CGSize
    /// Limits and feel.
    public var configuration: ZoomConfiguration

    /// Creates a state. Without a `scale`, the content starts at the configuration's minimum scale.
    public init(
        contentSize: CGSize,
        viewportSize: CGSize,
        configuration: ZoomConfiguration = .default,
        scale: CGFloat? = nil,
        offset: CGSize = .zero
    ) {
        self.contentSize = contentSize
        self.viewportSize = viewportSize
        self.configuration = configuration
        self.scale = scale ?? configuration.scaleRange.lowerBound
        self.offset = offset
    }

    // MARK: - Reading

    /// The lowest scale gestures settle at.
    public var minimumScale: CGFloat { configuration.scaleRange.lowerBound }

    /// The highest scale gestures settle at.
    public var maximumScale: CGFloat { configuration.scaleRange.upperBound }

    /// Whether the content is zoomed in beyond the minimum scale (with a small tolerance for
    /// floating-point noise after animations).
    public var isZoomed: Bool { scale > minimumScale + 0.001 }

    /// The size the content is drawn at.
    public var scaledContentSize: CGSize {
        CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    /// The center of the viewport in viewport coordinates.
    public var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    /// The scale at which content fitted into the viewport covers it completely, relative to the
    /// current content size. `1` when the content already fills the viewport in both directions.
    public var fillScale: CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        return max(1, viewportSize.width / contentSize.width, viewportSize.height / contentSize.height)
    }

    /// The point of the content shown at `viewportPoint`, in unit coordinates: `(0, 0)` is the
    /// content's top-left corner and `(1, 1)` its bottom-right corner. Values outside 0...1 are
    /// outside the content.
    public func contentPoint(at viewportPoint: CGPoint) -> CGPoint {
        guard contentSize.width > 0, contentSize.height > 0, scale > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let fromCenter = CGPoint(
            x: (viewportPoint.x - viewportCenter.x - offset.width) / scale,
            y: (viewportPoint.y - viewportCenter.y - offset.height) / scale
        )
        return CGPoint(x: fromCenter.x / contentSize.width + 0.5, y: fromCenter.y / contentSize.height + 0.5)
    }

    /// Where the content point at `unitPoint` (see ``contentPoint(at:)``) appears in the viewport.
    public func viewportPoint(forContentPoint unitPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: viewportCenter.x + offset.width + scale * (unitPoint.x - 0.5) * contentSize.width,
            y: viewportCenter.y + offset.height + scale * (unitPoint.y - 0.5) * contentSize.height
        )
    }

    // MARK: - Scale

    /// `scale` limited to the minimum and maximum scale.
    public func clampedScale(_ scale: CGFloat) -> CGFloat {
        ZoomMath.clamp(scale, to: configuration.scaleRange)
    }

    /// `scale` with resistance beyond the limits, for showing a pinch in progress.
    ///
    /// Within the limits it is returned unchanged. Beyond the maximum it grows ever more slowly and
    /// stays below `maximum × (1 + scaleOvershoot)`; below the minimum it shrinks ever more slowly
    /// and stays above `minimum / (1 + scaleOvershoot)`. The result is continuous and increasing.
    public func rubberBandedScale(_ scale: CGFloat) -> CGFloat {
        let range = configuration.scaleRange
        let overshoot = configuration.scaleOvershoot
        guard overshoot > 0 else { return clampedScale(scale) }
        if scale > range.upperBound {
            let excess = scale / range.upperBound - 1
            return range.upperBound * (1 + ZoomMath.rubberBand(excess, dimension: overshoot))
        }
        if scale < range.lowerBound {
            let excess = range.lowerBound / max(scale, .ulpOfOne) - 1
            return range.lowerBound / (1 + ZoomMath.rubberBand(excess, dimension: overshoot))
        }
        return scale
    }

    /// The state zoomed to `newScale` around `anchor`, a point in viewport coordinates (top-left
    /// origin): the content under the anchor stays under it. Neither the scale nor the offset is
    /// clamped; call ``settled(anchor:)`` for that.
    public func zoomed(to newScale: CGFloat, anchor: CGPoint) -> ZoomState {
        guard scale > 0, newScale > 0 else { return self }
        let ratio = newScale / scale
        let anchorFromCenter = CGSize(width: anchor.x - viewportCenter.x, height: anchor.y - viewportCenter.y)
        var result = self
        result.scale = newScale
        result.offset = CGSize(
            width: anchorFromCenter.width - ratio * (anchorFromCenter.width - offset.width),
            height: anchorFromCenter.height - ratio * (anchorFromCenter.height - offset.height)
        )
        return result
    }

    /// The state zoomed to `newScale` (clamped) with the content point `unitPoint` (see
    /// ``contentPoint(at:)``) moved as close to the viewport's center as the pan limits allow.
    public func zoomed(to newScale: CGFloat, centeredOn unitPoint: CGPoint) -> ZoomState {
        var result = self
        result.scale = clampedScale(newScale)
        let target = CGSize(
            width: -(unitPoint.x - 0.5) * contentSize.width * result.scale,
            height: -(unitPoint.y - 0.5) * contentSize.height * result.scale
        )
        result.offset = result.clampedOffset(target)
        return result
    }

    /// The state for a ``ZoomTarget``.
    public func zoomed(to target: ZoomTarget) -> ZoomState {
        zoomed(to: target.scale, centeredOn: target.anchor)
    }

    /// The state after a double tap (or double click) at `location` in viewport coordinates.
    ///
    /// When zoomed in it resets to the minimum scale, centered. Otherwise it zooms to
    /// `configuration.doubleTapScale` around the tapped point, so the detail under the finger stays
    /// under it, then keeps the image edges inside the viewport.
    public func doubleTapTarget(at location: CGPoint) -> ZoomState {
        if isZoomed {
            return reset()
        }
        let target = clampedScale(configuration.doubleTapScale)
        guard target > scale + 0.001 else { return reset() }
        return zoomed(to: target, anchor: location).settled()
    }

    /// The state at the minimum scale, centered.
    public func reset() -> ZoomState {
        var result = self
        result.scale = minimumScale
        result.offset = .zero
        return result
    }

    /// The state with the scale clamped (zooming around `anchor`, the viewport center by default)
    /// and the offset clamped so the content's edges stay outside the viewport (or centered where
    /// the content is smaller than the viewport). This is where a gesture ends up.
    public func settled(anchor: CGPoint? = nil) -> ZoomState {
        let target = clampedScale(scale)
        var result = self
        if target != scale {
            result = zoomed(to: target, anchor: anchor ?? viewportCenter)
        }
        result.offset = result.clampedOffset(result.offset)
        return result
    }

    // MARK: - Pan

    /// How far the content can move from the center in each direction at `scale` (the current
    /// scale when `nil`) without an edge entering the viewport. Zero in a direction where the
    /// content is not larger than the viewport.
    public func maximumOffset(at scale: CGFloat? = nil) -> CGSize {
        let scale = scale ?? self.scale
        return CGSize(
            width: max(0, (contentSize.width * scale - viewportSize.width) / 2),
            height: max(0, (contentSize.height * scale - viewportSize.height) / 2)
        )
    }

    /// `offset` limited so the content's edges never leave the viewport's edges at `scale` (the
    /// current scale when `nil`).
    public func clampedOffset(_ offset: CGSize, at scale: CGFloat? = nil) -> CGSize {
        let bound = maximumOffset(at: scale)
        return CGSize(
            width: ZoomMath.clamp(offset.width, to: -bound.width...bound.width),
            height: ZoomMath.clamp(offset.height, to: -bound.height...bound.height)
        )
    }

    /// `offset` with rubber-band resistance beyond the pan limits, for showing a drag in progress.
    /// Without `configuration.rubberBandsEdges` it is clamped instead.
    public func rubberBandedOffset(_ offset: CGSize, at scale: CGFloat? = nil) -> CGSize {
        guard configuration.rubberBandsEdges else { return clampedOffset(offset, at: scale) }
        let bound = maximumOffset(at: scale)
        return CGSize(
            width: Self.band(offset.width, limit: bound.width, dimension: viewportSize.width),
            height: Self.band(offset.height, limit: bound.height, dimension: viewportSize.height)
        )
    }

    /// The state panned from `startOffset` by a drag `translation`, rubber-banded at the edges.
    public func panned(from startOffset: CGSize, by translation: CGSize) -> ZoomState {
        var result = self
        result.offset = rubberBandedOffset(
            CGSize(width: startOffset.width + translation.width, height: startOffset.height + translation.height)
        )
        return result
    }

    private static func band(_ value: CGFloat, limit: CGFloat, dimension: CGFloat) -> CGFloat {
        if value > limit {
            return limit + ZoomMath.rubberBand(value - limit, dimension: dimension)
        }
        if value < -limit {
            return -limit - ZoomMath.rubberBand(-limit - value, dimension: dimension)
        }
        return value
    }
}
