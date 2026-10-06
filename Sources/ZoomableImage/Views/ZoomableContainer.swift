import SwiftUI

/// Callbacks a gallery passes to the page it shows; the public views leave them empty.
struct ZoomableHooks {
    /// Whether this page is the one on screen. Leaving the screen resets the zoom.
    var isActive = true
    /// Horizontal drags on a page that is not zoomed in go to the gallery's pager.
    var pager: PageDragHandler?
    /// A single tap or click (the gallery toggles its controls).
    var onTap: (() -> Void)?
    /// Called when the content becomes zoomed in or returns to the minimum scale.
    var onZoomChange: ((Bool) -> Void)?
    /// Called with the swipe-to-dismiss progress, 0...1.
    var onDismissProgress: ((CGFloat) -> Void)?
}

/// Receives horizontal drags for paging.
struct PageDragHandler {
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translation: CGFloat, _ predictedEndTranslation: CGFloat) -> Void
}

/// The view that does the zooming for ``ZoomableImage``, ``ZoomableView`` and ``ImageGallery``.
///
/// The content is centered in the available space, measured, then scaled and moved by the values
/// of a ``ZoomState``. All gestures are attached to the untransformed container, so their
/// locations are in viewport coordinates, exactly what the math expects.
struct ZoomableContainer<Content: View>: View {
    private let configuration: ZoomConfiguration
    private let initialZoom: ZoomTarget?
    private let onDismiss: (() -> Void)?
    private let hooks: ZoomableHooks
    private let content: Content

    @State private var scale: CGFloat
    @State private var offset: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var magnification: MagnificationStart?
    @State private var drag: DragStart?
    @State private var dismissTranslation: CGSize = .zero
    @State private var hasAppliedInitialZoom = false

    @Environment(\.zoomablePreviewDismissTranslation) private var previewDismissTranslation

    init(
        configuration: ZoomConfiguration,
        initialZoom: ZoomTarget?,
        onDismiss: (() -> Void)?,
        hooks: ZoomableHooks,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.initialZoom = initialZoom
        self.onDismiss = onDismiss
        self.hooks = hooks
        self.content = content()
        _scale = State(initialValue: configuration.scaleRange.lowerBound)
    }

    var body: some View {
        let dismiss = dismissState
        GeometryReader { proxy in
            content
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: { size in
                    contentSize = size
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale * dismiss.contentScale)
                .offset(
                    x: offset.width + dismiss.contentOffset.width,
                    y: offset.height + dismiss.contentOffset.height
                )
        }
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            viewportSize = size
        }
        .contentShape(Rectangle())
        .gesture(dragGesture, including: isDragEnabled ? .all : .subviews)
        .simultaneousGesture(magnifyGesture)
        .onTapGesture(count: 2) { location in
            doubleTap(at: location)
        }
        .onTapGesture(count: 1) {
            hooks.onTap?()
        }
        #if os(macOS)
        .background {
            ScrollWheelReader { input in
                handleScroll(input)
            }
        }
        #endif
        .onAppear {
            applyInitialZoomIfNeeded()
            reportPreviewDismissProgress()
        }
        .onChange(of: contentSize) {
            applyInitialZoomIfNeeded()
            resettleIfIdle()
        }
        .onChange(of: viewportSize) {
            applyInitialZoomIfNeeded()
            resettleIfIdle()
        }
        .onChange(of: hooks.isActive) { _, isActive in
            if !isActive {
                reset(animated: false)
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            hooks.onZoomChange?(zoomed)
        }
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text(isZoomed ? "Zoom out" : "Zoom in")) {
            let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
            doubleTap(at: center)
        }
    }

    // MARK: - State

    private var state: ZoomState {
        ZoomState(
            contentSize: contentSize,
            viewportSize: viewportSize,
            configuration: configuration,
            scale: scale,
            offset: offset
        )
    }

    private var isZoomed: Bool {
        state.isZoomed
    }

    private var canDismiss: Bool {
        onDismiss != nil && configuration.dismissal.isEnabled
    }

    /// A drag is only claimed when it does something, so a `ZoomableImage` that is not zoomed
    /// leaves vertical drags to an enclosing `ScrollView`.
    private var isDragEnabled: Bool {
        isZoomed || hooks.pager != nil || canDismiss
    }

    private var dismissState: DismissState {
        var translation = dismissTranslation
        if translation == .zero, hooks.isActive, let preview = previewDismissTranslation {
            translation = preview
        }
        return DismissState(translation: translation, configuration: configuration.dismissal)
    }

    private func apply(_ state: ZoomState) {
        scale = state.scale
        offset = state.offset
    }

    private static var settleAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.86)
    }

    // MARK: - Pinch

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                magnifyChanged(magnification: value.magnification, startLocation: value.startLocation)
            }
            .onEnded { _ in
                magnifyEnded()
            }
    }

    private func magnifyChanged(magnification value: CGFloat, startLocation: CGPoint) {
        if magnification == nil {
            magnification = MagnificationStart(scale: scale, offset: offset, anchor: startLocation)
            // A pinch takes over from a drag in progress.
            drag = nil
            if dismissTranslation != .zero {
                dismissTranslation = .zero
                hooks.onDismissProgress?(0)
            }
        }
        guard let start = magnification else { return }
        var base = state
        base.scale = start.scale
        base.offset = start.offset
        let target = base.zoomed(to: base.rubberBandedScale(start.scale * value), anchor: start.anchor)
        apply(target)
    }

    private func magnifyEnded() {
        guard let start = magnification else { return }
        magnification = nil
        let settled = state.settled(anchor: start.anchor)
        withAnimation(Self.settleAnimation) {
            apply(settled)
        }
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragChanged(translation: value.translation)
            }
            .onEnded { value in
                dragEnded(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    velocity: value.velocity
                )
            }
    }

    private func dragChanged(translation: CGSize) {
        guard magnification == nil else { return }
        if drag == nil {
            drag = DragStart(mode: dragMode(for: translation), offset: offset, translation: translation)
        }
        guard let start = drag else { return }
        switch start.mode {
        case .pan:
            let moved = CGSize(
                width: translation.width - start.translation.width,
                height: translation.height - start.translation.height
            )
            apply(state.panned(from: start.offset, by: moved))
        case .page:
            hooks.pager?.onChanged(translation.width)
        case .dismiss:
            dismissTranslation = translation
            hooks.onDismissProgress?(dismissState.progress)
        case .ignored:
            break
        }
    }

    private func dragEnded(translation: CGSize, predictedEndTranslation: CGSize, velocity: CGSize) {
        guard let start = drag else { return }
        drag = nil
        switch start.mode {
        case .pan:
            // Keep the flick's momentum, then stop at the edges.
            let predicted = CGSize(
                width: start.offset.width + predictedEndTranslation.width - start.translation.width,
                height: start.offset.height + predictedEndTranslation.height - start.translation.height
            )
            let target = state.clampedOffset(predicted)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                offset = target
            }
        case .page:
            hooks.pager?.onEnded(translation.width, predictedEndTranslation.width)
        case .dismiss:
            let release = DismissState(translation: translation, configuration: configuration.dismissal)
            let dismisses = release.shouldDismiss(velocity: velocity)
            withAnimation(Self.settleAnimation) {
                dismissTranslation = .zero
                hooks.onDismissProgress?(0)
                if dismisses {
                    onDismiss?()
                }
            }
        case .ignored:
            break
        }
    }

    private func dragMode(for translation: CGSize) -> DragMode {
        if isZoomed {
            return .pan
        }
        let isHorizontal = abs(translation.width) > abs(translation.height)
        if isHorizontal, hooks.pager != nil {
            return .page
        }
        if canDismiss, DismissState.isDismissDrag(translation: translation, configuration: configuration.dismissal) {
            return .dismiss
        }
        if hooks.pager != nil {
            return .page
        }
        // Content that fills the viewport can be panned without zooming in.
        if state.maximumOffset() != .zero {
            return .pan
        }
        return .ignored
    }

    // MARK: - Double tap

    private func doubleTap(at location: CGPoint) {
        guard contentSize != .zero, viewportSize != .zero else { return }
        let target = state.doubleTapTarget(at: location)
        withAnimation(Self.settleAnimation) {
            apply(target)
        }
    }

    // MARK: - Mac scroll wheel

    #if os(macOS)
    private func handleScroll(_ input: ScrollWheelInput) -> Bool {
        guard hooks.isActive, contentSize != .zero, viewportSize != .zero else { return false }
        let lineHeight: CGFloat = input.hasPreciseDeltas ? 1 : 12
        let delta = CGSize(width: input.delta.width * lineHeight, height: input.delta.height * lineHeight)
        if input.isZoomModifierPressed {
            // ⌥ + scroll zooms around the pointer: about 2x per 70 points of scrolling.
            let factor = CGFloat(pow(2, Double(delta.height) / 70))
            let current = state
            let target = current.zoomed(to: current.clampedScale(scale * factor), anchor: input.location)
            var settled = target
            settled.offset = target.clampedOffset(target.offset)
            apply(settled)
            return true
        }
        guard isZoomed || state.maximumOffset() != .zero else { return false }
        let moved = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        offset = state.clampedOffset(moved)
        return true
    }
    #endif

    // MARK: - Lifecycle

    private func applyInitialZoomIfNeeded() {
        guard !hasAppliedInitialZoom, let initialZoom, hooks.isActive,
              contentSize.width > 1, contentSize.height > 1,
              viewportSize.width > 1, viewportSize.height > 1
        else { return }
        hasAppliedInitialZoom = true
        apply(state.zoomed(to: initialZoom))
    }

    private func resettleIfIdle() {
        guard magnification == nil, drag == nil else { return }
        let settled = state.settled()
        if settled != state {
            apply(settled)
        }
    }

    private func reset(animated: Bool) {
        let target = state.reset()
        if animated {
            withAnimation(Self.settleAnimation) { apply(target) }
        } else {
            apply(target)
        }
        dismissTranslation = .zero
    }

    private func reportPreviewDismissProgress() {
        guard hooks.isActive, previewDismissTranslation != nil else { return }
        hooks.onDismissProgress?(dismissState.progress)
    }
}

private enum DragMode {
    case pan
    case page
    case dismiss
    case ignored
}

private struct DragStart {
    var mode: DragMode
    var offset: CGSize
    var translation: CGSize
}

private struct MagnificationStart {
    var scale: CGFloat
    var offset: CGSize
    var anchor: CGPoint
}
