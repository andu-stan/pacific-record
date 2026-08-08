import Foundation

/// Data shared between the app and its widgets.
///
/// A widget runs in its own process and can't reach the app's Documents
/// folder — and even if it could, opening SQLite and decoding a
/// full-resolution cover inside a widget's tight memory budget would be a bad
/// idea. So the app writes a small snapshot (JSON plus a handful of downsampled
/// covers) into a shared App Group container, and the widget only ever reads
/// that.
///
/// This file is compiled into **both** targets.
enum WidgetShared {
    /// Must match the App Groups capability on both targets.
    static let appGroupID = "group.ro.sofistic.pacificrecord"

    static let snapshotFileName = "widget-snapshot.json"
    static let coversDirectoryName = "WidgetCovers"

    /// How many records the rotation pool holds. Small enough to keep the
    /// shared container tiny, large enough that a daily pick rarely repeats.
    static let poolSize = 60

    /// The shared container, or nil if the App Group isn't configured.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    static var coversURL: URL? {
        containerURL?.appendingPathComponent(coversDirectoryName, isDirectory: true)
    }

    /// Resolves a cover file name to its location in the shared container.
    static func coverURL(named name: String) -> URL? {
        coversURL?.appendingPathComponent(name)
    }

    // MARK: Reading / writing

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        guard let url = snapshotURL else { throw WidgetSharedError.noContainer }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    enum WidgetSharedError: Error {
        /// The App Group isn't set up — the capability is missing from a target.
        case noContainer
    }
}

/// What the widgets draw. Deliberately tiny and self-contained.
struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var libraryName: String
    var recordCount: Int
    var artistCount: Int
    var genreCount: Int
    /// Pre-formatted, since the widget shouldn't need currency rules.
    var formattedValue: String?
    var valuedCount: Int
    /// The rotation pool for "record of the day".
    var records: [WidgetRecord]

    static let empty = WidgetSnapshot(
        generatedAt: .distantPast,
        libraryName: "Library",
        recordCount: 0,
        artistCount: 0,
        genreCount: 0,
        formattedValue: nil,
        valuedCount: 0,
        records: []
    )

    /// The record for a given day, stable within that day and across widget
    /// refreshes — the index comes from the date itself, not from randomness.
    func record(forDayOffset offset: Int, from date: Date = Date()) -> WidgetRecord? {
        guard !records.isEmpty else { return nil }
        let day = Int(date.timeIntervalSince1970 / 86_400) + offset
        // Mix the day number so consecutive days don't walk the pool in order.
        var hash = UInt64(bitPattern: Int64(day &* 2_654_435_761))
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        return records[Int(hash % UInt64(records.count))]
    }
}

/// One record, flattened for display.
struct WidgetRecord: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var year: Int?
    var format: String?
    var rating: Int
    /// File name inside the shared covers directory, if a cover was copied.
    var coverFile: String?

    /// "1959 · LP" — whatever of the two is known.
    var detailLine: String {
        [year.map(String.init), format].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Deep link used by the widgets: `pacificrecord://record/<id>`.
enum WidgetDeepLink {
    static let scheme = "pacificrecord"

    static func record(_ id: String) -> URL? {
        URL(string: "\(scheme)://record/\(id)")
    }

    static var library: URL? {
        URL(string: "\(scheme)://library")
    }

    static var stats: URL? {
        URL(string: "\(scheme)://stats")
    }

    /// Extracts a record id from an incoming URL, if it is one.
    static func recordID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "record" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }
}
