import CoreGraphics
import Foundation

/// The swipe-to-dismiss math: how far along a dismiss drag is, how the image and the background
/// follow it, and whether releasing it closes the viewer.
///
/// ```swift
/// let state = DismissState(translation: CGSize(width: 12, height: 160))
/// state.progress            // 0.5 (160 of 320 points)
/// state.backgroundOpacity   // 0.5
/// state.contentScale        // 0.85
/// state.shouldDismiss(velocity: CGSize(width: 0, height: 200))   // true, past 120 points
/// ```
public struct DismissState: Equatable, Sendable {
    /// The drag translation since the gesture started.
    public var translation: CGSize
    /// Thresholds and visuals.
    public var configuration: DismissConfiguration

    public init(translation: CGSize = .zero, configuration: DismissConfiguration = DismissConfiguration()) {
        self.translation = translation
        self.configuration = configuration
    }

    /// Whether a drag that has moved by `translation` should become a dismiss drag rather than a
    /// page swipe: it must be mostly vertical and, unless upward swipes are allowed, go down.
    public static func isDismissDrag(translation: CGSize, configuration: DismissConfiguration = DismissConfiguration()) -> Bool {
        guard configuration.isEnabled else { return false }
        let vertical = abs(translation.height)
        guard vertical > 0, vertical >= abs(translation.width) else { return false }
        return configuration.allowsUpwardSwipe || translation.height > 0
    }

    /// The distance moved in the dismiss direction: down, or either way with upward swipes.
    public var dismissDistance: CGFloat {
        configuration.allowsUpwardSwipe ? abs(translation.height) : max(0, translation.height)
    }

    /// 0 when the drag starts, 1 once it has moved `fadeDistance` in the dismiss direction.
    public var progress: CGFloat {
        ZoomMath.clamp(dismissDistance / configuration.fadeDistance, to: 0...1)
    }

    /// The opacity of the viewer's background: 1 at rest, 0 at full progress.
    public var backgroundOpacity: Double {
        Double(1 - progress)
    }

    /// The scale of the image: 1 at rest, `minimumContentScale` at full progress.
    public var contentScale: CGFloat {
        1 - (1 - configuration.minimumContentScale) * progress
    }

    /// Where the image is drawn relative to its resting place. It follows the finger, except that
    /// pulling the wrong way (up, when only down dismisses) rubber-bands.
    public var contentOffset: CGSize {
        var offset = translation
        if !configuration.allowsUpwardSwipe, translation.height < 0 {
            offset.height = ZoomMath.rubberBand(translation.height, dimension: configuration.fadeDistance)
        }
        return offset
    }

    /// Whether releasing the drag with `velocity` (points per second, as reported by the drag
    /// gesture) closes the viewer.
    ///
    /// It closes after moving `distanceThreshold` in the dismiss direction, or after a short flick
    /// faster than `velocityThreshold` in that direction. Flicking back toward the start cancels,
    /// however far the drag went.
    public func shouldDismiss(velocity: CGSize) -> Bool {
        guard configuration.isEnabled else { return false }
        // The velocity along the direction the image was pulled, positive when moving away.
        let direction: CGFloat = translation.height < 0 ? -1 : 1
        let outward = velocity.height * direction
        if outward < -configuration.velocityThreshold / 2 {
            return false
        }
        if !configuration.allowsUpwardSwipe, translation.height <= 0 {
            return false
        }
        if dismissDistance >= configuration.distanceThreshold {
            return true
        }
        return outward >= configuration.velocityThreshold && dismissDistance >= 16
    }
}
