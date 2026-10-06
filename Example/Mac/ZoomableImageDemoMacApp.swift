import AppKit
import SwiftUI
import ZoomableImage

@main
struct ZoomableImageDemoMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Trailbook") {
            if ScreenshotScene.current == nil {
                JournalView()
                    .frame(minWidth: 760, minHeight: 520)
            } else {
                // Screenshot scenes use their own borderless window; this one is hidden at once.
                WindowHider()
            }
        }
        .defaultSize(width: 1180, height: 760)
    }
}

/// Shows a screenshot scene when CI asks for one.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenshot: ScreenshotWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let scene = ScreenshotScene.current {
            screenshot = ScreenshotWindow(scene: scene, renderPath: ScreenshotScene.renderPath)
        }
    }
}

/// Hides the window it is placed in.
private struct WindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HidingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Task { @MainActor in
                window.orderOut(nil)
            }
        }
    }
}
