import SwiftUI

private struct PreviewDismissTranslationKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

extension EnvironmentValues {
    /// A swipe-to-dismiss translation to draw without a gesture, for previews and screenshots.
    var zoomablePreviewDismissTranslation: CGSize? {
        get { self[PreviewDismissTranslationKey.self] }
        set { self[PreviewDismissTranslationKey.self] = newValue }
    }
}

extension View {
    /// Draws the visible zoomable image (or gallery page) as if it were being swiped away by
    /// `translation`, with the background faded to match. For previews and screenshots only:
    /// import with `@_spi(Previews) import ZoomableImage`.
    @_spi(Previews)
    public func zoomablePreviewDismiss(translation: CGSize) -> some View {
        environment(\.zoomablePreviewDismissTranslation, translation)
    }
}
