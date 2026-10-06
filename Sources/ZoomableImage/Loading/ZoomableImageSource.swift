import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Where an image comes from: an `Image` you already have, a URL, or your own async loader.
///
/// ```swift
/// .image(Image("Summit"))
/// .url(URL(string: "https://example.com/summit.jpg")!)
/// .url(Bundle.main.url(forResource: "summit", withExtension: "jpg")!)
/// .provider(id: photo.id) { try await library.fullImage(for: photo.id) }
/// ```
///
/// URL and provider images are loaded once and kept in a small in-memory cache, so the grid, the
/// thumbnails strip and the viewer share them.
public enum ZoomableImageSource: Sendable {
    /// An image that is ready to draw.
    case image(Image)
    /// An image file on the web (`https`) or on disk (`file`), in any format the platform decodes.
    case url(URL)
    /// An image produced by your own code, for example from the Photos library or a database.
    /// `id` identifies the image for caching and must be unique per image.
    case provider(id: String, load: @Sendable () async throws -> Image)

    /// The cache key, `nil` for images that need no loading.
    var loadingKey: String? {
        switch self {
        case .image: nil
        case .url(let url): "url:" + url.absoluteString
        case .provider(let id, _): "provider:" + id
        }
    }

    /// An image from the app's asset catalog (or another bundle's).
    public static func asset(_ name: String, bundle: Bundle? = nil) -> ZoomableImageSource {
        .image(Image(name, bundle: bundle))
    }

    #if canImport(UIKit)
    /// A `UIImage`.
    public static func uiImage(_ image: UIImage) -> ZoomableImageSource {
        .image(Image(uiImage: image))
    }
    #elseif canImport(AppKit)
    /// An `NSImage`.
    public static func nsImage(_ image: NSImage) -> ZoomableImageSource {
        .image(Image(nsImage: image))
    }
    #endif
}

/// Why a URL image could not be shown.
public enum ZoomableImageError: Error, Equatable, Sendable {
    /// The server answered with a status code outside 200...299.
    case badStatus(Int)
    /// The data is not an image the platform can decode.
    case undecodableData
}

/// The state of a loading image, as ``LoadableImage`` reports it.
public enum LoadableImagePhase {
    /// Still loading.
    case empty
    /// Loaded.
    case success(Image)
    /// Loading failed.
    case failure(any Error)

    /// The image, once loaded.
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
}

/// Loads and caches images for URL and provider sources.
@MainActor
enum ImageLoader {
    private static var cache: [String: Image] = [:]
    private static var recentKeys: [String] = []
    private static let capacity = 80

    static func cachedImage(for source: ZoomableImageSource) -> Image? {
        switch source {
        case .image(let image):
            return image
        case .url, .provider:
            guard let key = source.loadingKey else { return nil }
            return cache[key]
        }
    }

    static func image(for source: ZoomableImageSource) async throws -> Image {
        if let cached = cachedImage(for: source) {
            return cached
        }
        let image: Image
        switch source {
        case .image(let ready):
            return ready
        case .url(let url):
            let data = try await data(from: url)
            guard let decoded = decode(data) else { throw ZoomableImageError.undecodableData }
            image = decoded
        case .provider(_, let load):
            image = try await load()
        }
        if let key = source.loadingKey {
            store(image, for: key)
        }
        return image
    }

    private static func data(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ZoomableImageError.badStatus(http.statusCode)
        }
        return data
    }

    private static func decode(_ data: Data) -> Image? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }

    private static func store(_ image: Image, for key: String) {
        if cache[key] == nil {
            recentKeys.append(key)
        }
        cache[key] = image
        while recentKeys.count > capacity {
            let oldest = recentKeys.removeFirst()
            cache[oldest] = nil
        }
    }
}
