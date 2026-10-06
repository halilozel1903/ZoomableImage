import SwiftUI
import ZoomableImage

@main
struct ZoomableImageDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if let scene = ScreenshotScene.current {
                ScreenshotView(scene: scene)
            } else {
                JournalView()
            }
        }
    }
}
