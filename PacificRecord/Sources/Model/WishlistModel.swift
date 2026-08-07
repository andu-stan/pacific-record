import Foundation
import Observation
import VinylCore

/// Records you want but don't own, with optional Discogs price tracking.
@MainActor
@Observable
final class WishlistModel {
    /// UserDefaults keys for the optional tabs.
    static let showStatsKey = "showStatsTab"
    static let showWishlistKey = "showWishlistTab"

    private let store: LibraryStore
    private let libraryFolder: URL

    private(set) var items: [WishlistItem] = []
    private(set) var isRefreshing = false
    private(set) var refreshProgress: Double = 0
    var inStockOnly = false

    init(store: LibraryStore, libraryFolder: URL) {
        self.store = store
        self.libraryFolder = libraryFolder
        reload()
    }

    func reload() {
        items = (try? store.wishlist()) ?? []
    }

    /// The entries actually shown, honouring the in-stock filter.
    var visibleItems: [WishlistItem] {
        inStockOnly ? items.filter(\.isInStock) : items
    }

    var trackedCount: Int { items.filter { $0.discogsReleaseID != nil }.count }

    // MARK: Editing

    /// Adds a release found through the Discogs search, skipping duplicates.
    @discardableResult
    func add(from match: MetadataMatch) async -> Bool {
        let existing = (try? store.wishlistDiscogsIDs()) ?? []
        if let releaseID = match.discogsReleaseID, existing.contains(releaseID) { return false }

        let id = UUID().uuidString
        var thumbPath: String?
        if let url = match.coverImageURL,
           let result = try? await CoverImageManager().downloadCover(from: url, releaseID: "wish-\(id)", into: libraryFolder) {
            thumbPath = result.thumbPath ?? result.coverPath
        }
        let item = WishlistItem(
            id: id,
            title: match.title,
            artistDisplay: match.artistDisplay,
            year: match.year,
            discogsReleaseID: match.discogsReleaseID,
            thumbPath: thumbPath
        )
        try? store.saveWishlistItem(item)
        reload()
        return true
    }

    func addManual(title: String, artist: String, notes: String?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let item = WishlistItem(
            title: clean,
            artistDisplay: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes?.isEmpty == true ? nil : notes
        )
        try? store.saveWishlistItem(item)
        reload()
    }

    func delete(_ item: WishlistItem) {
        try? store.deleteWishlistItem(id: item.id)
        reload()
    }

    // MARK: Price tracking

    /// Re-checks every linked entry's lowest listing and stock, paced by one
    /// shared rate-limited client.
    func refreshPrices() async {
        guard !isRefreshing else { return }
        let tracked = items.filter { $0.discogsReleaseID != nil }
        guard !tracked.isEmpty else { return }

        isRefreshing = true
        refreshProgress = 0
        let client = RecordValueService.makeClient()
        let currency = RecordValueService.preferredCurrency

        for (index, item) in tracked.enumerated() {
            guard let releaseID = item.discogsReleaseID else { continue }
            if let snapshot = try? await client.marketplaceSnapshot(releaseID: releaseID, currency: currency) {
                var updated = item
                // Keep the prior observation so the row can show the movement.
                updated.previousPrice = item.lastPrice
                updated.lastPrice = snapshot.price?.amount
                updated.lastCurrency = snapshot.price?.currency ?? currency
                updated.numForSale = snapshot.numForSale
                updated.priceCheckedAt = Date()
                try? store.saveWishlistItem(updated)
            }
            refreshProgress = Double(index + 1) / Double(tracked.count)
        }
        reload()
        isRefreshing = false
        Haptics.success()
    }
}

// MARK: - Display helpers

extension WishlistItem {
    var subtitle: String {
        var parts: [String] = []
        if !artistDisplay.isEmpty { parts.append(artistDisplay) }
        if let year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }

    var formattedPrice: String? {
        guard let lastPrice, let lastCurrency else { return nil }
        return lastPrice.formatted(.currency(code: lastCurrency))
    }

    /// "−4.00" / "+6.00" / "no change", or nil before the second check.
    var formattedDelta: String? {
        guard let delta = priceDelta, let currency = lastCurrency else { return nil }
        if delta == 0 { return "no change" }
        let sign = delta < 0 ? "−" : "+"
        return sign + abs(delta).formatted(.currency(code: currency))
    }

    var statusText: String {
        guard priceCheckedAt != nil else { return "Not checked yet" }
        guard let count = numForSale, count > 0 else { return "Not in stock" }
        return count == 1 ? "1 for sale" : "\(count) for sale"
    }
}
