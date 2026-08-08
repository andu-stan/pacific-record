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
    var locations: [Location] = []
    var availableGenres: [String] = []
    var availableFormats: [String] = []

    /// Mutated only through `setFilter`/`updateFilter` so the derived state
    /// below can never go stale.
    private(set) var filter = LibraryFilter()

    /// The records actually shown: the fetched list narrowed by the facet
    /// filter. Stored rather than computed — the Library screen reads this (and
    /// the counts below) several times per render, and re-filtering the whole
    /// library each time showed up while scrolling and during selection.
    private(set) var visibleRecords: [Release] = []
    private(set) var artistCount = 0
    /// User-given name for the collection, from the database.
    private(set) var libraryName: String?
    private(set) var genreCount = 0
    /// Sum of the visible records' estimated value, grouped by currency (so it
    /// reflects the current filter).
    private(set) var totalValueByCurrency: [String: Double] = [:]

    /// Drives the "update every value" run from Settings; lives here so it
    /// keeps going after that sheet is dismissed.
    private(set) var valueRefresh: ValueRefreshCoordinator
    /// Wishlist state, sharing this library's store and cover folder.
    private(set) var wishlist: WishlistModel

    init(store: LibraryStore, libraryFolder: URL) {
        self.store = store
        self.libraryFolder = libraryFolder
        self.valueRefresh = ValueRefreshCoordinator(store: store)
        self.wishlist = WishlistModel(store: store, libraryFolder: libraryFolder)
        reload()
        reloadLocations()
        refreshFacets()
        reloadName()
        valueRefresh.onChange = { [weak self] in self?.reload() }
    }

    /// Re-reads everything — the pull-to-refresh entry point.
    func refreshAll() {
        reload()
        reloadLocations()
        refreshFacets()
        reloadName()
    }

    // MARK: Library name

    func reloadName() {
        libraryName = (try? store.libraryName()) ?? nil
    }

    func setLibraryName(_ name: String?) {
        try? store.setLibraryName(name)
        reloadName()
    }

    /// What to show at the top of the Library screen.
    var displayName: String { libraryName ?? "Library" }

    func startValueRefresh() {
        valueRefresh.start(records: records)
    }

    var count: Int { visibleRecords.count }

    /// True only when the whole library is empty (not merely filtered/searched
    /// to nothing) — that's when the onboarding empty state should show.
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
        applyFilter()
    }

    // MARK: Filtering

    func setFilter(_ newValue: LibraryFilter) {
        filter = newValue
        applyFilter()
    }

    /// Change one facet in place, e.g. `updateFilter { $0.sync = .notSynced }`.
    func updateFilter(_ mutate: (inout LibraryFilter) -> Void) {
        var updated = filter
        mutate(&updated)
        setFilter(updated)
    }

    func clearFilter() {
        setFilter(LibraryFilter())
    }

    /// Recomputes the visible list and its summary counts. Called whenever the
    /// records or the filter change.
    private func applyFilter() {
        visibleRecords = filter.isActive ? records.filter(filter.matches) : records

        var artists = Set<String>()
        var genres = Set<String>()
        var totals: [String: Double] = [:]
        artists.reserveCapacity(visibleRecords.count)
        for record in visibleRecords {
            artists.insert(record.artistDisplay)
            if let genre = record.genre, !genre.isEmpty { genres.insert(genre) }
            if let amount = record.estimatedValue, let currency = record.valueCurrency {
                totals[currency, default: 0] += amount
            }
        }
        artistCount = artists.count
        genreCount = genres.count
        totalValueByCurrency = totals
        refreshWidgetsIfNeeded()
    }

    /// Signature of what the widgets show, so a snapshot is only rewritten when
    /// something they display actually changed — `applyFilter` also runs on
    /// every search keystroke.
    @ObservationIgnored private var widgetSignature: Int = 0

    private func refreshWidgetsIfNeeded() {
        var hasher = Hasher()
        hasher.combine(records.count)
        hasher.combine(libraryName)
        hasher.combine(artistCount)
        hasher.combine(genreCount)
        for record in records { hasher.combine(record.id) }
        let signature = hasher.finalize()
        guard signature != widgetSignature else { return }
        widgetSignature = signature

        WidgetSnapshotWriter.update(
            records: records,
            libraryName: displayName,
            artistCount: artistCount,
            genreCount: genreCount,
            formattedValue: totalValueByCurrency.isEmpty ? nil : formattedTotalValue,
            valuedCount: records.filter { $0.estimatedValue != nil }.count,
            libraryFolder: libraryFolder
        )
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
        refreshFacets()
    }

    func delete(_ release: Release) {
        try? store.delete(id: release.id)
        reload()
        refreshFacets()
    }

    // MARK: Bulk actions

    /// Assigns (or clears, with `nil`) the location of the given records.
    func setLocation(_ locationID: String?, for ids: Set<String>) {
        guard !ids.isEmpty else { return }
        try? store.setLocation(locationID, forReleaseIDs: Array(ids))
        reload()
    }

    /// Deletes the given records in one transaction.
    func delete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        try? store.delete(ids: Array(ids))
        reload()
        refreshFacets()
    }

    /// Builds a shareable copy of the library (see `LibraryExporter`).
    func exportLibrary(_ format: LibraryExporter.Format) async throws -> LibraryExporter.ExportFile {
        try await LibraryExporter.export(format, store: store, libraryFolder: libraryFolder)
    }

    /// Restores from a backup, then refreshes everything on screen.
    func importLibrary(
        _ preview: LibraryImporter.Preview,
        mode: LibraryImporter.Mode,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> LibraryImporter.Summary {
        let summary = try await LibraryImporter.apply(
            preview, mode: mode, into: store, libraryFolder: libraryFolder, progress: progress)
        refreshAll()
        return summary
    }

    /// Distinct genres/formats present in the library, for the filter sheet.
    func refreshFacets() {
        availableGenres = (try? store.genres()) ?? []
        availableFormats = (try? store.formats()) ?? []
    }

    /// Builds an importer wired to this library's store and cover folder, and
    /// refreshes the library as records stream in.
    func makeDiscogsImporter(token: String) -> DiscogsCollectionImporter {
        DiscogsCollectionImporter(token: token, store: store, libraryFolder: libraryFolder) { [weak self] in
            self?.reload()
            self?.refreshFacets()
        }
    }

    // MARK: Discogs sync-back

    /// Pushes a record to the user's Discogs collection and, on success (added or
    /// already there), persists the synced marker so the filter reflects it.
    @discardableResult
    func syncToDiscogs(_ release: Release) async -> DiscogsSyncOutcome {
        let outcome = await DiscogsCollectionSync.push(release)
        switch outcome {
        case .added, .alreadyInCollection:
            try? store.setDiscogsSynced(id: release.id)
            reload()
        case .failed, .notLinked:
            break
        }
        return outcome
    }

    /// Fire-and-forget auto-sync for a freshly added record when the toggle is on.
    func autoSyncToDiscogs(_ release: Release) {
        guard DiscogsCollectionSync.autoSyncEnabled, release.discogsReleaseID != nil else { return }
        Task { await syncToDiscogs(release) }
    }

    /// Looks the value up in the background once a record is fully graded —
    /// the estimate is condition-specific, so this also re-runs after a re-grade.
    func autoEstimateValue(for release: Release) {
        guard release.mediaCondition != nil, release.sleeveCondition != nil else { return }
        guard RecordValueService.needsValue(release) else { return }
        Task {
            if let estimate = await RecordValueService.fetch(for: release) {
                setValue(amount: estimate.amount, currency: estimate.currency,
                         basis: estimate.basis, for: release)
            }
        }
    }

    func setValue(amount: Double, currency: String, basis: String, for release: Release) {
        // Re-fetch the current record so we only change the value fields and
        // never clobber others (media/sleeve, rating, notes…) from a stale
        // snapshot captured before an edit.
        guard var updated = try? store.detail(id: release.id)?.release else { return }
        updated.estimatedValue = amount
        updated.valueCurrency = currency
        updated.valueBasis = basis
        updated.valueUpdatedAt = Date()
        try? store.update(updated)
        reload()
    }

    // MARK: Locations

    func reloadLocations() {
        locations = (try? store.locations()) ?? []
    }

    var defaultLocation: Location? { locations.first(where: { $0.isDefault }) }

    func location(id: String?) -> Location? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }

    @discardableResult
    func addLocation(_ name: String) -> Location? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = try? store.addLocation(name: trimmed)
        reloadLocations()
        return created
    }

    func renameLocation(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.renameLocation(id: id, name: trimmed)
        reloadLocations()
    }

    func setDefaultLocation(_ id: String) {
        try? store.setDefaultLocation(id: id)
        reloadLocations()
    }

    func deleteLocation(_ id: String) {
        try? store.deleteLocation(id: id)
        reloadLocations()
        reload()
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
        case .valueDescending: return "Value"
        }
    }
}
