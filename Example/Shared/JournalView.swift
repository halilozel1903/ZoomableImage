import SwiftUI
import ZoomableImage

/// Trailbook's only screen: the trips as sections of a photo grid. Tapping a photo opens the
/// gallery, which grows out of the grid cell and shrinks back into it when it is closed.
struct JournalView: View {
    @State private var selection: JournalEntry.ID?
    @Namespace private var namespace
    private let initialZoom: ZoomTarget?

    init(selection: JournalEntry.ID? = nil, initialZoom: ZoomTarget? = nil) {
        _selection = State(initialValue: selection)
        self.initialZoom = initialZoom
    }

    var body: some View {
        container
            .imageGallery(
                items: Journal.entries,
                selection: $selection,
                namespace: namespace,
                initialZoom: initialZoom,
                source: { $0.photo },
                thumbnail: { $0.thumbnail }
            ) { entry in
                EntryCaption(entry: entry)
            }
    }

    @ViewBuilder
    private var container: some View {
        #if os(iOS)
        NavigationStack {
            grid
                .navigationTitle("Trailbook")
        }
        #else
        grid
        #endif
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                #if os(macOS)
                MacHeader()
                #endif
                ForEach(Journal.trips) { trip in
                    VStack(alignment: .leading, spacing: 10) {
                        TripHeader(trip: trip)
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(trip.entries) { entry in
                                cell(for: entry)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func cell(for entry: JournalEntry) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                LoadableImage(source: entry.thumbnail, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .galleryTransitionSource(id: entry.id, selection: selection, in: namespace)
            .onTapGesture {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    selection = entry.id
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(entry.title))
            .accessibilityAddTraits(.isButton)
    }

    private var columns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 170), spacing: spacing)]
        #else
        return [GridItem(.adaptive(minimum: 118), spacing: spacing)]
        #endif
    }

    private var spacing: CGFloat {
        #if os(macOS)
        return 8
        #else
        return 2
        #endif
    }

    private var cornerRadius: CGFloat {
        #if os(macOS)
        return 8
        #else
        return 0
        #endif
    }
}

private struct TripHeader: View {
    let trip: JournalTrip

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title)
                    .font(.title3.weight(.bold))
                Text(trip.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trip.entries.count == 1 ? "1 photo" : "\(trip.entries.count) photos")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

#if os(macOS)
private struct MacHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trailbook")
                .font(.largeTitle.weight(.bold))
            Text("\(Journal.entries.count) photos from \(Journal.trips.count) trips. Click a photo, then pinch, ⌥-scroll or double-click to zoom.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }
}
#endif

/// The caption the gallery shows above the thumbnails.
struct EntryCaption: View {
    let entry: JournalEntry

    var body: some View {
        VStack(spacing: 3) {
            Text(entry.title)
                .font(.headline)
            Text("\(entry.place) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }
}
