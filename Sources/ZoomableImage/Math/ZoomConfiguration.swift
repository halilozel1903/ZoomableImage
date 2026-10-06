import CoreGraphics
import Foundation

/// Limits and feel of zooming, panning and swipe-to-dismiss.
///
/// ```swift
/// var configuration = ZoomConfiguration()
/// configuration.maximumScale = 6
/// configuration.doubleTapScale = 3
/// configuration.dismissal.allowsUpwardSwipe = true
/// ZoomableImage(image: Image("Summit"), configuration: configuration)
/// ```
public struct ZoomConfiguration: Equatable, Hashable, Sendable {
    /// The smallest scale a gesture settles at. `1` shows the whole image (or fills the viewport
    /// with `contentMode = .fill`).
    public var minimumScale: CGFloat

    /// The largest scale a gesture settles at.
    public var maximumScale: CGFloat

    /// The scale a double tap (or double click) zooms to. Clamped to the minimum and maximum.
    public var doubleTapScale: CGFloat

    /// How content is sized at the minimum scale.
    public var contentMode: ZoomContentMode

    /// How far a pinch can go past the limits, as a fraction of the limit. `0.35` lets a pinch
    /// reach 35% beyond `maximumScale` (with growing resistance) before it springs back.
    public var scaleOvershoot: CGFloat

    /// Whether panning past an edge rubber-bands (`true`) or stops hard at the edge (`false`).
    public var rubberBandsEdges: Bool

    /// Swipe-to-dismiss thresholds and visuals.
    public var dismissal: DismissConfiguration

    /// Creates a configuration. Invalid limits are corrected by ``scaleRange``: the minimum scale is
    /// at least 0.1 and the maximum is never below the minimum.
    public init(
        minimumScale: CGFloat = 1,
        maximumScale: CGFloat = 4,
        doubleTapScale: CGFloat = 2.5,
        contentMode: ZoomContentMode = .fit,
        scaleOvershoot: CGFloat = 0.35,
        rubberBandsEdges: Bool = true,
        dismissal: DismissConfiguration = DismissConfiguration()
    ) {
        self.minimumScale = minimumScale
        self.maximumScale = maximumScale
        self.doubleTapScale = doubleTapScale
        self.contentMode = contentMode
        self.scaleOvershoot = max(0, scaleOvershoot)
        self.rubberBandsEdges = rubberBandsEdges
        self.dismissal = dismissal
    }

    /// Scales from 1x to 4x, double tap to 2.5x, fit, rubber-banding and swipe down to dismiss.
    public static let `default` = ZoomConfiguration()

    /// The range gestures settle into: `minimumScale...maximumScale`, corrected so the lower bound
    /// is at least 0.1 and the upper bound is never below it.
    public var scaleRange: ClosedRange<CGFloat> {
        let lower = max(0.1, minimumScale.isFinite ? minimumScale : 1)
        let upper = max(lower, maximumScale.isFinite ? maximumScale : lower)
        return lower...upper
    }
}

/// When a vertical drag on an image that is not zoomed in closes the viewer, and how the image and
/// the background follow the finger.
public struct DismissConfiguration: Equatable, Hashable, Sendable {
    /// Whether swiping dismisses at all. Has no effect without an `onDismiss` action.
    public var isEnabled: Bool

    /// Dismisses when the finger is released at least this far (points) from where it started.
    public var distanceThreshold: CGFloat

    /// Dismisses a shorter swipe when it is released faster than this (points per second) in the
    /// dismiss direction.
    public var velocityThreshold: CGFloat

    /// The distance over which the background fades out and the image shrinks.
    public var fadeDistance: CGFloat

    /// The image scale at full progress, for example 0.7 for 70%.
    public var minimumContentScale: CGFloat

    /// Whether a swipe up dismisses too. By default only a swipe down does, and pulling up
    /// rubber-bands.
    public var allowsUpwardSwipe: Bool

    public init(
        isEnabled: Bool = true,
        distanceThreshold: CGFloat = 120,
        velocityThreshold: CGFloat = 700,
        fadeDistance: CGFloat = 320,
        minimumContentScale: CGFloat = 0.7,
        allowsUpwardSwipe: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.distanceThreshold = max(0, distanceThreshold)
        self.velocityThreshold = max(0, velocityThreshold)
        self.fadeDistance = max(1, fadeDistance)
        self.minimumContentScale = ZoomMath.clamp(minimumContentScale, to: 0.1...1)
        self.allowsUpwardSwipe = allowsUpwardSwipe
    }
}

/// A scale and a point of the image to center, for opening an image already zoomed in.
public struct ZoomTarget: Equatable, Sendable {
    /// The zoom scale; clamped to the configuration's range.
    public var scale: CGFloat
    /// The point of the image to bring to the center, in unit coordinates: `(0, 0)` is the image's
    /// top-left corner, `(1, 1)` its bottom-right corner. The pan limits still apply, so a corner
    /// ends up as close to the center as the image edges allow.
    public var anchor: CGPoint

    public init(scale: CGFloat, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.scale = scale
        self.anchor = anchor
    }
}
