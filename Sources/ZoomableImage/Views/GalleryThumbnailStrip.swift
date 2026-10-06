import SwiftUI

/// The strip of thumbnails at the bottom of ``ImageGallery``. The current image is wider and
/// outlined, and the strip keeps it centered.
struct GalleryThumbnailStrip<Item: Identifiable>: View {
    let items: [Item]
    let currentIndex: Int
    let thumbnail: (Item) -> ZoomableImageSource
    let onSelect: (Int) -> Void

    #if os(macOS)
    private let height: CGFloat = 56
    #else
    private let height: CGFloat = 48
    #endif

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                        let isCurrent = position == currentIndex
                        Button {
                            onSelect(position)
                        } label: {
                            LoadableImage(source: thumbnail(item), contentMode: .fill)
                                .frame(width: isCurrent ? height * 1.15 : height * 0.68, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(.white, lineWidth: isCurrent ? 2 : 0)
                                }
                                .opacity(isCurrent ? 1 : 0.72)
                                .padding(.horizontal, isCurrent ? 4 : 0)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityLabel(Text("Image \(position + 1)"))
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .frame(height: height)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .frame(height: height + 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: currentIndex)
            .onChange(of: currentIndex, initial: true) { _, newIndex in
                guard items.indices.contains(newIndex) else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    reader.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

extension View {
    /// Marks a grid cell as where the gallery image with `id` opens from and closes back to.
    ///
    /// While `selection` is `id`, the cell is hidden, so the image seems to lift out of the grid,
    /// and to land back in its place when the gallery closes. Use the same `namespace` for
    /// ``ImageGallery`` or ``imageGallery(items:selection:namespace:configuration:showsThumbnails:initialZoom:source:thumbnail:)``.
    public func galleryTransitionSource<ID: Hashable>(id: ID, selection: ID?, in namespace: Namespace.ID) -> some View {
        modifier(GalleryTransitionSource(id: AnyHashable(id), isOpen: selection == id, namespace: namespace))
    }

    /// Shows an ``ImageGallery`` over this view while `selection` is not `nil`.
    ///
    /// Apply it to a view that covers the screen (or the window on the Mac), such as the
    /// `NavigationStack` around your grid. Change `selection` inside `withAnimation` to animate
    /// the transition.
    public func imageGallery<Item: Identifiable>(
        items: [Item],
        selection: Binding<Item.ID?>,
        namespace: Namespace.ID? = nil,
        configuration: ZoomConfiguration = .default,
        showsThumbnails: Bool = true,
        initialZoom: ZoomTarget? = nil,
        source: @escaping (Item) -> ZoomableImageSource,
        thumbnail: ((Item) -> ZoomableImageSource)? = nil
    ) -> some View {
        imageGallery(
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

    /// Shows an ``ImageGallery`` with an accessory view, such as a caption, over this view while
    /// `selection` is not `nil`.
    public func imageGallery<Item: Identifiable, Accessory: View>(
        items: [Item],
        selection: Binding<Item.ID?>,
        namespace: Namespace.ID? = nil,
        configuration: ZoomConfiguration = .default,
        showsThumbnails: Bool = true,
        initialZoom: ZoomTarget? = nil,
        source: @escaping (Item) -> ZoomableImageSource,
        thumbnail: ((Item) -> ZoomableImageSource)? = nil,
        @ViewBuilder accessory: @escaping (Item) -> Accessory
    ) -> some View {
        overlay {
            if selection.wrappedValue != nil {
                ImageGallery(
                    items: items,
                    selection: selection,
                    namespace: namespace,
                    configuration: configuration,
                    showsThumbnails: showsThumbnails,
                    initialZoom: initialZoom,
                    source: source,
                    thumbnail: thumbnail,
                    accessory: accessory
                )
                .transition(.opacity)
            }
        }
    }
}

private struct GalleryTransitionSource: ViewModifier {
    let id: AnyHashable
    let isOpen: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .matchedGeometryEffect(id: isOpen ? AnyHashable(OpenSource(id: id)) : id, in: namespace)
            .opacity(isOpen ? 0 : 1)
    }

    private struct OpenSource: Hashable {
        let id: AnyHashable
    }
}
