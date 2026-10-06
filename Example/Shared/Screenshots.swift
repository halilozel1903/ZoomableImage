import SwiftUI
@_spi(Previews) import ZoomableImage

/// Scenes used by CI to capture the README screenshots on iPhone, iPad and the Mac.
///
/// Launch with `-screenshot <scene>`; normal launches are unaffected. An `iphone-`, `ipad-` or
/// `mac-` prefix is accepted too, so `-screenshot ipad-gallery` is the same as `-screenshot gallery`.
enum ScreenshotScene: String {
    /// The journal grid.
    case grid
    /// The hut photo open in the gallery, zoomed to 2.5x on the cabin.
    case zoomed
    /// A photo halfway through a swipe down: smaller, lower, the grid showing through.
    case dismiss
    /// The gallery with its caption and thumbnails strip (iPad).
    case gallery
    /// The gallery in the Mac window.
    case viewer

    static var current: ScreenshotScene? {
        guard var name = argument(after: "-screenshot") else { return nil }
        for prefix in ["iphone-", "ipad-", "mac-"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return ScreenshotScene(rawValue: name)
    }

    /// Where `-render-screenshot` asks the PNG to be written (Mac only).
    static var renderPath: String? {
        argument(after: "-render-screenshot")
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    /// The photo open in the gallery.
    var selection: JournalEntry.ID? {
        switch self {
        case .grid: nil
        case .zoomed: "alpine-dawn"
        case .dismiss: "golden-valley"
        case .gallery: "quiet-fjord"
        case .viewer: "mirror-lake"
        }
    }

    /// The zoom the open photo starts at: the cabin with the lit window.
    var initialZoom: ZoomTarget? {
        switch self {
        case .zoomed: ZoomTarget(scale: 2.5, anchor: CGPoint(x: 0.64, y: 0.71))
        default: nil
        }
    }

    /// A swipe-to-dismiss drag frozen halfway.
    var dismissTranslation: CGSize? {
        switch self {
        case .dismiss: CGSize(width: 14, height: 190)
        default: nil
        }
    }
}

/// Renders one scene of the real app with a fixed selection, zoom and drag.
struct ScreenshotView: View {
    let scene: ScreenshotScene

    var body: some View {
        content
            .task {
                // Tells scripts/screenshots.sh that the scene is on screen.
                let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshot-ready")
                try? await Task.sleep(for: .seconds(1.5))
                try? scene.rawValue.write(to: marker, atomically: true, encoding: .utf8)
            }
    }

    @ViewBuilder
    private var content: some View {
        let journal = JournalView(selection: scene.selection, initialZoom: scene.initialZoom)
        if let translation = scene.dismissTranslation {
            journal.zoomablePreviewDismiss(translation: translation)
        } else {
            journal
        }
    }
}
