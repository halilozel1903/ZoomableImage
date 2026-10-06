import SwiftUI

/// A full-screen viewer for a list of images, like Photos: swipe between pages, pinch and double
/// tap to zoom, a strip of thumbnails to jump around, swipe down to close, and a matched-geometry
/// transition from and back to the grid cell the image was opened from.
///
/// The easiest way to use it is the ``SwiftUICore/View/imageGallery(items:selection:namespace:configuration:showsThumbnails:initialZoom:source:thumbnail:)``
/// modifier, which shows the gallery while `selection` is not `nil`:
///
/// ```swift
/// @State private var selection: Photo.ID?
/// @Namespace private var namespace
///
/// LazyVGrid(columns: columns) {
///     ForEach(photos) { photo in
///         LoadableImage(source: .url(photo.thumbnailURL), contentMode: .fill)
///             .galleryTransitionSource(id: photo.id, selection: selection, in: namespace)
///             .onTapGesture {
///                 withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { selection = photo.id }
///             }
///     }
/// }
/// .imageGallery(items: photos, selection: $selection, namespace: namespace) { photo in
///     .url(photo.url)
/// }
/// ```
///
/// `selection` follows the page on screen and becomes `nil` when the gallery is closed with the
/// close button, a swipe down or the Escape key.
public struct ImageGallery<Item: Identifiable, Accessory: View>: View {
    private let items: [Item]
    @Binding private var selection: Item.ID?
    private let namespace: Namespace.ID?
    private let configuration: ZoomConfiguration
    private let showsThumbnails: Bool
    private let initialZoom: ZoomTarget?
    private let source: (Item) -> ZoomableImageSource
    private let thumbnail: ((Item) -> ZoomableImageSource)?
    private let accessory: (Item) -> Accessory

    @State private var index: Int
    @State private var initialSelection: Item.ID?
    @State private var pageTranslation: CGFloat = 0
    @State private var dismissProgress: CGFloat = 0
    @State private var showsControls = true
    @FocusState private var isFocused: Bool

    private let pageSpacing: CGFloat = 16

    /// Creates a gallery.
    ///
    /// - Parameters:
    ///   - items: The images, in order.
    ///   - selection: The item on screen. Paging updates it; closing sets it to `nil`.
    ///   - namespace: The namespace of the grid's ``SwiftUICore/View/galleryTransitionSource(id:selection:in:)``
    ///     modifiers, for the open and close transition. Without it the gallery fades.
    ///   - configuration: Zoom limits and swipe-to-dismiss.
    ///   - showsThumbnails: Whether to show the strip of thumbnails at the bottom.
    ///   - initialZoom: A zoom to show the first page at.
    ///   - source: The full-size image of an item.
    ///   - thumbnail: A smaller image for the thumbnails strip; the full image when `nil`.
    ///   - accessory: A view shown above the thumbnails for the current item, such as a caption.
    public init(
        items: [Item],
        selection: Binding<Item.ID?>,
        namespace: Namespace.ID? = nil,
        configuration: ZoomConfiguration = .default,
        showsThumbnails: Bool = true,
        initialZoom: ZoomTarget? = nil,
        source: @escaping (Item) -> ZoomableImageSource,
        thumbnail: ((Item) -> ZoomableImageSource)? = nil,
        @ViewBuilder accessory: @escaping (Item) -> Accessory
    ) {
        self.items = items
        _selection = selection
        self.namespace = namespace
        self.configuration = configuration
        self.showsThumbnails = showsThumbnails
        self.initialZoom = initialZoom
        self.source = source
        self.thumbnail = thumbnail
        self.accessory = accessory
        let start = items.firstIndex { $0.id == selection.wrappedValue } ?? 0
        _index = State(initialValue: start)
        _initialSelection = State(initialValue: selection.wrappedValue)
    }

    public var body: some View {
        ZStack {
            Color.black
                .opacity(Double(1 - dismissProgress))
                .ignoresSafeArea()

            pager
                .ignoresSafeArea()

            if !items.isEmpty {
                controls
                    .opacity(showsControls ? Double(max(0, 1 - dismissProgress * 3)) : 0)
                    .allowsHitTesting(showsControls && dismissProgress == 0)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            go(to: index - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            go(to: index + 1)
            return .handled
        }
        .onAppear {
            isFocused = true
        }
        .onChange(of: selection) {
            // The selection changed from outside, for example from the grid.
            guard let selection, let newIndex = items.firstIndex(where: { $0.id == selection }), newIndex != index else { return }
            index = newIndex
        }
        .onChange(of: items.count) {
            index = min(index, max(0, items.count - 1))
        }
    }

    // MARK: - Pages

    private var pager: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let current = clampedIndex
            HStack(spacing: pageSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    Group {
                        if abs(position - current) <= 1 {
                            page(for: item, at: position, isCurrent: position == current, pageWidth: size.width)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
            .offset(
                x: GalleryPaging.stripOffset(index: current, pageWidth: size.width, spacing: pageSpacing)
                    + GalleryPaging.offset(for: pageTranslation, current: current, count: items.count, pageWidth: size.width)
            )
        }
    }

    private func page(for item: Item, at position: Int, isCurrent: Bool, pageWidth: CGFloat) -> some View {
        var hooks = ZoomableHooks()
        hooks.isActive = isCurrent
        hooks.pager = items.count > 1 ? pageHandler(pageWidth: pageWidth) : nil
        hooks.onTap = {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsControls.toggle()
            }
        }
        hooks.onDismissProgress = { progress in
            dismissProgress = progress
        }
        var image = ZoomableImage(
            source: source(item),
            configuration: configuration,
            initialZoom: item.id == initialSelection ? initialZoom : nil,
            onDismiss: { close() },
            placeholder: {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        )
        image.hooks = hooks
        // Only the visible page takes part in the open and close transition.
        let matchedID: AnyHashable = isCurrent ? AnyHashable(item.id) : AnyHashable(InactivePage(position: position))
        return image
            .modifier(OptionalMatchedGeometry(id: matchedID, namespace: namespace))
            .accessibilityLabel(Text("Image \(position + 1) of \(items.count)"))
    }

    private func pageHandler(pageWidth: CGFloat) -> PageDragHandler {
        PageDragHandler(
            onChanged: { translation in
                pageTranslation = translation
            },
            onEnded: { _, predicted in
                pageEnded(predictedEndTranslation: predicted, pageWidth: pageWidth)
            }
        )
    }

    private func pageEnded(predictedEndTranslation: CGFloat, pageWidth: CGFloat) {
        let target = GalleryPaging.targetIndex(
            current: clampedIndex,
            count: items.count,
            predictedEndTranslation: predictedEndTranslation,
            pageWidth: pageWidth
        )
        go(to: target)
    }

    /// Moves to `target` with a spring and updates `selection` without animating it, so the grid
    /// cells behind the gallery swap instantly instead of flying across the screen.
    private func go(to target: Int) {
        guard !items.isEmpty else { return }
        let target = min(max(target, 0), items.count - 1)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            index = target
            pageTranslation = 0
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selection = items[target].id
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            selection = nil
        }
    }

    private var clampedIndex: Int {
        min(max(index, 0), max(0, items.count - 1))
    }

    // MARK: - Controls

    private var controls: some View {
        let item = items[clampedIndex]
        return VStack(spacing: 0) {
            HStack {
                GalleryCloseButton(action: close)
                Spacer()
                Text("\(clampedIndex + 1) of \(items.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                accessory(item)
                if showsThumbnails, items.count > 1 {
                    GalleryThumbnailStrip(
                        items: items,
                        currentIndex: clampedIndex,
                        thumbnail: thumbnail ?? source,
                        onSelect: { go(to: $0) }
                    )
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            .background {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

extension ImageGallery where Accessory == EmptyView {
    /// Creates a gallery without an accessory view.
    public init(
        items: [Item],
        selection: Binding<Item.ID?>,
        namespace: Namespace.ID? = nil,
        configuration: ZoomConfiguration = .default,
        showsThumbnails: Bool = true,
        initialZoom: ZoomTarget? = nil,
        source: @escaping (Item) -> ZoomableImageSource,
        thumbnail: ((Item) -> ZoomableImageSource)? = nil
    ) {
        self.init(
            items: items,
            selection: selection,
            namespace: namespace,
            configuration: configuration,
            showsThumbnails: showsThumbnails,
            initialZoom: initialZoom,
            source: source,
            thumbnail: thumbnail,
            accessory: { _ in EmptyView() }
        )
    }
}

private struct InactivePage: Hashable {
    let position: Int
}

/// Applies `matchedGeometryEffect` when there is a namespace.
struct OptionalMatchedGeometry: ViewModifier {
    let id: AnyHashable
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// The round close button of the gallery.
struct GalleryCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(Text("Close"))
    }
}
