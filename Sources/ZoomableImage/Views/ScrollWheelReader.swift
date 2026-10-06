#if os(macOS)
import AppKit
import SwiftUI

/// A scroll-wheel or two-finger trackpad scroll over a zoomable view on the Mac.
struct ScrollWheelInput {
    /// The scroll distance (`scrollingDeltaX`, `scrollingDeltaY`); already in points for trackpads
    /// and Magic Mouse, in lines for classic mouse wheels.
    var delta: CGSize
    /// Where the pointer is, in the view's coordinates (top-left origin).
    var location: CGPoint
    /// Whether ⌥ Option is held, which turns scrolling into zooming.
    var isZoomModifierPressed: Bool
    /// `true` for trackpads and Magic Mouse, `false` for line-based mouse wheels.
    var hasPreciseDeltas: Bool
}

/// Watches scroll-wheel events over the view it is placed behind, without taking clicks, drags or
/// gestures away from SwiftUI. `onScroll` returns `true` to consume an event (the zoomable view
/// zoomed or panned) and `false` to let it scroll whatever is underneath.
struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (ScrollWheelInput) -> Bool

    func makeNSView(context: Context) -> ScrollWheelMonitorView {
        let view = ScrollWheelMonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelMonitorView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollWheelMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class ScrollWheelMonitorView: NSView {
    var onScroll: ((ScrollWheelInput) -> Bool)?
    private var monitor: Any?

    override var isFlipped: Bool { true }

    // Never the target of clicks: SwiftUI's gestures on top keep working.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Read everything from the event first, then handle it on the main actor (local
            // monitors are called on the main thread).
            let input = ScrollWheelEventValues(
                delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
                locationInWindow: event.locationInWindow,
                windowNumber: event.windowNumber,
                isOptionPressed: event.modifierFlags.contains(.option),
                hasPreciseDeltas: event.hasPreciseScrollingDeltas
            )
            let consumed = MainActor.assumeIsolated {
                self?.handle(input) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func handle(_ values: ScrollWheelEventValues) -> Bool {
        guard let window, window.windowNumber == values.windowNumber, let onScroll else { return false }
        let location = convert(values.locationInWindow, from: nil)
        guard bounds.contains(location) else { return false }
        return onScroll(
            ScrollWheelInput(
                delta: values.delta,
                location: location,
                isZoomModifierPressed: values.isOptionPressed,
                hasPreciseDeltas: values.hasPreciseDeltas
            )
        )
    }
}

private struct ScrollWheelEventValues: Sendable {
    var delta: CGSize
    var locationInWindow: CGPoint
    var windowNumber: Int
    var isOptionPressed: Bool
    var hasPreciseDeltas: Bool
}
#endif
