import SwiftUI

/// An image you can pinch to zoom, double tap, pan and, optionally, swipe away, like in Photos.
///
/// ```swift
/// ZoomableImage(image: Image("Summit"))
///
/// ZoomableImage(url: photo.url) {
///     showsPhoto = false                    // swipe down to dismiss
/// }
/// ```
///
/// - iPhone and iPad: pinch with two fingers, drag to pan, double tap to zoom in on a detail or
///   back out, swipe down to dismiss when an `onDismiss` action is set.
/// - Mac: pinch on the trackpad, ⌥ Option + scroll to zoom around the pointer, drag or scroll to
///   pan, double click to zoom in or out.
///
/// The image fits the available space (or fills it, see ``ZoomConfiguration/contentMode``) and
/// its edges never leave the view's edges; pinching and panning past the limits rubber-bands.
public struct ZoomableImage<Placeholder: View>: View {
    private let source: ZoomableImageSource
    private let configuration: ZoomConfiguration
    private let initialZoom: ZoomTarget?
    private let dismissProgress: Binding<CGFloat>?
    private let onDismiss: (() -> Void)?
    private let placeholder: Placeholder
    var hooks = ZoomableHooks()

    /// Creates a zoomable image with your own placeholder, shown while a URL or provider image
    /// loads.
    ///
    /// - Parameters:
    ///   - source: The image, a URL, or an async provider.
    ///   - configuration: Scale limits, double tap scale, content mode and swipe-to-dismiss.
    ///   - initialZoom: A scale and image point to show first, for example a face.
    ///   - dismissProgress: Receives the swipe-to-dismiss progress (0...1) while the image is
    ///     dragged, to fade your own background.
    ///   - onDismiss: Called when a swipe down is released past the threshold. Without it, swiping
    ///     does nothing and vertical drags reach an enclosing scroll view.
    ///   - placeholder: Shown while the image loads.
    public init(
        source: ZoomableImageSource,
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        dismissProgress: Binding<CGFloat>? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.source = source
        self.configuration = configuration
        self.initialZoom = initialZoom
        self.dismissProgress = dismissProgress
        self.onDismiss = onDismiss
        self.placeholder = placeholder()
    }

    public var body: some View {
        LoadableImage(source: source) { phase in
            switch phase {
            case .success(let image):
                ZoomableContainer(
                    configuration: configuration,
                    initialZoom: initialZoom,
                    onDismiss: onDismiss,
                    hooks: containerHooks
                ) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: configuration.contentMode.swiftUIContentMode)
                }
            case .empty:
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                ZoomableImageFailureView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var containerHooks: ZoomableHooks {
        var hooks = hooks
        let forward = hooks.onDismissProgress
        let binding = dismissProgress
        if forward != nil || binding != nil {
            hooks.onDismissProgress = { progress in
                binding?.wrappedValue = progress
                forward?(progress)
            }
        }
        return hooks
    }
}

extension ZoomableImage where Placeholder == ZoomableImagePlaceholder {
    /// Creates a zoomable image.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - configuration: Scale limits, double tap scale, content mode and swipe-to-dismiss.
    ///   - initialZoom: A scale and image point to show first.
    ///   - dismissProgress: Receives the swipe-to-dismiss progress (0...1).
    ///   - onDismiss: Called when a swipe down is released past the threshold.
    public init(
        image: Image,
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        dismissProgress: Binding<CGFloat>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            source: .image(image),
            configuration: configuration,
            initialZoom: initialZoom,
            dismissProgress: dismissProgress,
            onDismiss: onDismiss
        )
    }

    /// Creates a zoomable image loaded from a web or file URL, with a spinner while it loads.
    public init(
        url: URL,
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        dismissProgress: Binding<CGFloat>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            source: .url(url),
            configuration: configuration,
            initialZoom: initialZoom,
            dismissProgress: dismissProgress,
            onDismiss: onDismiss
        )
    }

    /// Creates a zoomable image from any source, with a spinner while it loads.
    public init(
        source: ZoomableImageSource,
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        dismissProgress: Binding<CGFloat>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            source: source,
            configuration: configuration,
            initialZoom: initialZoom,
            dismissProgress: dismissProgress,
            onDismiss: onDismiss,
            placeholder: { ZoomableImagePlaceholder() }
        )
    }
}

/// Makes any view zoomable: pinch, double tap, pan and optional swipe-to-dismiss, with the same
/// behavior as ``ZoomableImage``.
///
/// ```swift
/// ZoomableView {
///     MapSnapshot(trail: trail)
///         .aspectRatio(3 / 2, contentMode: .fit)
/// }
/// ```
///
/// The content is measured at its natural size inside the available space, so give it a size or
/// an aspect ratio.
public struct ZoomableView<Content: View>: View {
    private let configuration: ZoomConfiguration
    private let initialZoom: ZoomTarget?
    private let dismissProgress: Binding<CGFloat>?
    private let onDismiss: (() -> Void)?
    private let content: Content

    public init(
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        dismissProgress: Binding<CGFloat>? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.initialZoom = initialZoom
        self.dismissProgress = dismissProgress
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZoomableContainer(
            configuration: configuration,
            initialZoom: initialZoom,
            onDismiss: onDismiss,
            hooks: hooks
        ) {
            content
        }
    }

    private var hooks: ZoomableHooks {
        var hooks = ZoomableHooks()
        if let dismissProgress {
            hooks.onDismissProgress = { progress in
                dismissProgress.wrappedValue = progress
            }
        }
        return hooks
    }
}

extension View {
    /// Makes this view zoomable. See ``ZoomableView``.
    public func zoomable(
        configuration: ZoomConfiguration = .default,
        initialZoom: ZoomTarget? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        ZoomableView(configuration: configuration, initialZoom: initialZoom, onDismiss: onDismiss) {
            self
        }
    }
}

/// The default placeholder of ``ZoomableImage``: a spinner.
public struct ZoomableImagePlaceholder: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .controlSize(.large)
    }
}

/// Shown when an image cannot be loaded.
struct ZoomableImageFailureView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text("The image could not be loaded.")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension ZoomContentMode {
    var swiftUIContentMode: ContentMode {
        switch self {
        case .fit: .fit
        case .fill: .fill
        }
    }
}
