import SwiftUI

/// Shows a ``ZoomableImageSource`` without zooming, for grid cells and thumbnails. It shares the
/// cache with ``ZoomableImage`` and ``ImageGallery``, so an image loaded for the grid opens
/// instantly in the viewer.
///
/// ```swift
/// LoadableImage(source: .url(photo.thumbnailURL), contentMode: .fill)
///     .frame(width: 120, height: 120)
///     .clipped()
///
/// LoadableImage(source: .url(photo.url)) { phase in
///     if let image = phase.image {
///         image.resizable().scaledToFit()
///     } else {
///         Color.gray.opacity(0.2)
///     }
/// }
/// ```
public struct LoadableImage<Content: View>: View {
    private let source: ZoomableImageSource
    private let content: (LoadableImagePhase) -> Content

    @State private var loaded: Loaded?
    @State private var failed: Failed?

    /// Calls `content` with the loading phase.
    public init(source: ZoomableImageSource, @ViewBuilder content: @escaping (LoadableImagePhase) -> Content) {
        self.source = source
        self.content = content
    }

    public var body: some View {
        content(phase)
            .task(id: source.loadingKey) {
                await load()
            }
    }

    private var phase: LoadableImagePhase {
        if let image = ImageLoader.cachedImage(for: source) {
            return .success(image)
        }
        let key = source.loadingKey
        if let loaded, loaded.key == key {
            return .success(loaded.image)
        }
        if let failed, failed.key == key {
            return .failure(failed.error)
        }
        return .empty
    }

    private func load() async {
        guard let key = source.loadingKey, ImageLoader.cachedImage(for: source) == nil else { return }
        do {
            let image = try await ImageLoader.image(for: source)
            loaded = Loaded(key: key, image: image)
        } catch is CancellationError {
            // The view went away or the source changed; the next task loads again.
        } catch {
            if !Task.isCancelled {
                failed = Failed(key: key, error: error)
            }
        }
    }

    private struct Loaded {
        let key: String
        let image: Image
    }

    private struct Failed {
        let key: String
        let error: any Error
    }
}

extension LoadableImage where Content == LoadableImageDefaultContent {
    /// Shows the image resizable at `contentMode`, a soft placeholder while it loads and a photo
    /// symbol if it fails.
    public init(source: ZoomableImageSource, contentMode: ContentMode = .fit) {
        self.init(source: source) { phase in
            LoadableImageDefaultContent(phase: phase, contentMode: contentMode)
        }
    }
}

/// The content of ``LoadableImage/init(source:contentMode:)``.
public struct LoadableImageDefaultContent: View {
    let phase: LoadableImagePhase
    let contentMode: ContentMode

    public var body: some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
        case .empty:
            Rectangle()
                .fill(.quaternary)
        case .failure:
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
