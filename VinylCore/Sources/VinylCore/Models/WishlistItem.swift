import Foundation
import GRDB

/// A record you want but don't own yet, optionally linked to a Discogs release
/// so its marketplace price can be tracked.
public struct WishlistItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var artistDisplay: String
    public var year: Int?
    public var discogsReleaseID: Int?
    public var notes: String?
    /// Relative path inside the library folder, as for a record's cover.
    public var thumbPath: String?
    /// Latest observed lowest marketplace listing.
    public var lastPrice: Double?
    public var lastCurrency: String?
    /// The previous observation, so the UI can show which way the price moved.
    public var previousPrice: Double?
    public var priceCheckedAt: Date?
    /// Copies on sale at the last check; 0 means nothing listed right now.
    public var numForSale: Int?
    public var addedAt: Date

    public static let databaseTableName = "wishlist"

    public enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistDisplay = "artist_display"
        case year
        case discogsReleaseID = "discogs_release_id"
        case notes
        case thumbPath = "thumb_path"
        case lastPrice = "last_price"
        case lastCurrency = "last_currency"
        case previousPrice = "previous_price"
        case priceCheckedAt = "price_checked_at"
        case numForSale = "num_for_sale"
        case addedAt = "added_at"
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        artistDisplay: String,
        year: Int? = nil,
        discogsReleaseID: Int? = nil,
        notes: String? = nil,
        thumbPath: String? = nil,
        lastPrice: Double? = nil,
        lastCurrency: String? = nil,
        previousPrice: Double? = nil,
        priceCheckedAt: Date? = nil,
        numForSale: Int? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artistDisplay = artistDisplay
        self.year = year
        self.discogsReleaseID = discogsReleaseID
        self.notes = notes
        self.thumbPath = thumbPath
        self.lastPrice = lastPrice
        self.lastCurrency = lastCurrency
        self.previousPrice = previousPrice
        self.priceCheckedAt = priceCheckedAt
        self.numForSale = numForSale
        self.addedAt = addedAt
    }

    /// True when the last check found copies for sale.
    public var isInStock: Bool { (numForSale ?? 0) > 0 }

    /// Signed change since the previous observation, if both are known.
    public var priceDelta: Double? {
        guard let lastPrice, let previousPrice else { return nil }
        let delta = lastPrice - previousPrice
        return abs(delta) < 0.005 ? 0 : delta
    }
}
