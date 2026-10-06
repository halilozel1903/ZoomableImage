import Foundation
import SwiftUI
import ZoomableImage

/// One photo of Trailbook, a made-up travel journal. The photos are landscapes drawn by a script
/// (gradients, ridges, a sun and a few trees), bundled as JPEG files with a small thumbnail each.
struct JournalEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let place: String
    let date: Date

    /// The full-size photo, loaded from the app bundle by URL like a downloaded image would be.
    var photo: ZoomableImageSource {
        Self.source(named: id)
    }

    /// A 480-pixel version for the grid and the thumbnails strip.
    var thumbnail: ZoomableImageSource {
        Self.source(named: "\(id)-thumb")
    }

    private static func source(named name: String) -> ZoomableImageSource {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return .url(url)
        }
        return .image(Image(systemName: "photo"))
    }
}

/// A group of photos taken on one trip.
struct JournalTrip: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let entries: [JournalEntry]
}

enum Journal {
    static let trips: [JournalTrip] = [
        JournalTrip(
            id: "dolomites",
            title: "Dolomites",
            subtitle: "Hut to hut through South Tyrol",
            entries: [
                entry("alpine-dawn", "First light at the hut", "Rifugio Firenze, Italy", 2026, 10, 3),
                entry("misty-ridges", "Fog over Val di Funes", "Val di Funes, Italy", 2026, 10, 2),
                entry("golden-valley", "Golden hour above the valley", "Seceda, Italy", 2026, 10, 1),
                entry("snow-peaks", "First snow on the peaks", "Sassolungo, Italy", 2026, 9, 30),
                entry("autumn-hills", "Larches turning gold", "Alpe di Siusi, Italy", 2026, 9, 29),
            ]
        ),
        JournalTrip(
            id: "provence",
            title: "Provence",
            subtitle: "A week of lavender and long evenings",
            entries: [
                entry("lavender-fields", "Lavender at dusk", "Valensole, France", 2026, 7, 12),
            ]
        ),
        JournalTrip(
            id: "southwest",
            title: "Desert Southwest",
            subtitle: "Mesas, dust and very dark skies",
            entries: [
                entry("desert-dusk", "Sunset between the mesas", "Monument Valley, USA", 2026, 5, 18),
                entry("starry-camp", "Camp under the Milky Way", "Capitol Reef, USA", 2026, 5, 16),
            ]
        ),
        JournalTrip(
            id: "lofoten",
            title: "Lofoten",
            subtitle: "Late winter above the Arctic Circle",
            entries: [
                entry("aurora-bay", "Northern lights over the bay", "Uttakleiv, Norway", 2026, 3, 9),
                entry("quiet-fjord", "A red sail in the fjord", "Reinefjorden, Norway", 2026, 3, 8),
                entry("mirror-lake", "A perfectly still lake", "Flakstad, Norway", 2026, 3, 6),
                entry("ocean-sunset", "Sun on the open sea", "Haukland Beach, Norway", 2026, 3, 5),
            ]
        ),
    ]

    /// Every photo, newest trip first, in the order the gallery pages through them.
    static let entries: [JournalEntry] = trips.flatMap(\.entries)

    private static func entry(_ id: String, _ title: String, _ place: String, _ year: Int, _ month: Int, _ day: Int) -> JournalEntry {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
        return JournalEntry(id: id, title: title, place: place, date: date)
    }
}
