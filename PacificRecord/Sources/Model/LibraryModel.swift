import Foundation
import Observation
import VinylCore

enum LibraryLayout {
    case grid
    case list
}

/// Observable UI state over `VinylCore.LibraryStore`. Owns the current record
/// list plus the search/sort/layout the Library screen drives.
@MainActor
@Observable
final class LibraryModel {
    private let store: LibraryStore
    /// Folder holding the database and the `Covers/` directory.
    let libraryFolder: URL

    var records: [Release] = []
    var searchText: String = ""
    var sort: LibraryStore.SortOrder = .artist
    var layout: LibraryLayout = .grid

    init(store: LibraryStore, libraryFolder: URL) {
        self.store = store
        self.libraryFolder = libraryFolder
        reload()
    }

    var count: Int { records.count }

    var artistCount: Int {
        Set(records.map(\.artistDisplay)).count
    }

    var isEmpty: Bool { records.isEmpty && searchText.isEmpty }

    func reload() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            records = trimmed.isEmpty
                ? try store.allReleases(sortedBy: sort)
                : try store.search(trimmed)
        } catch {
            records = []
        }
    }

    func detail(for release: Release) -> RecordDetail? {
        try? store.detail(id: release.id)
    }

    func detail(id: String) -> RecordDetail? {
        try? store.detail(id: id)
    }

    func save(_ detail: RecordDetail) {
        try? store.save(detail)
        reload()
    }

    func delete(_ release: Release) {
        try? store.delete(id: release.id)
        reload()
    }

    func setValue(amount: Double, currency: String, basis: String, for release: Release) {
        var updated = release
        updated.estimatedValue = amount
        updated.valueCurrency = currency
        updated.valueBasis = basis
        updated.valueUpdatedAt = Date()
        try? store.update(updated)
        reload()
    }

    /// Sum of every record's estimated value, grouped by currency.
    var totalValueByCurrency: [String: Double] {
        var totals: [String: Double] = [:]
        for record in records {
            if let amount = record.estimatedValue, let currency = record.valueCurrency {
                totals[currency, default: 0] += amount
            }
        }
        return totals
    }

    /// Formatted collection total, e.g. "$312.50" (or several, joined, if the
    /// library mixes currencies).
    var formattedTotalValue: String {
        totalValueByCurrency
            .sorted { $0.key < $1.key }
            .map { $0.value.formatted(.currency(code: $0.key)) }
            .joined(separator: " + ")
    }
}

extension LibraryStore.SortOrder {
    var label: String {
        switch self {
        case .artist: return "Artist"
        case .title: return "Title"
        case .yearDescending: return "Year"
        case .dateAddedDescending: return "Recently added"
        case .ratingDescending: return "Rating"
        }
    }
}
