import Foundation
import VinylCore

/// Facet filters applied to the library list on top of the text search. These
/// are evaluated in memory over the fetched records.
struct LibraryFilter: Equatable {
    /// Location facet: any location, a specific one, or records with none.
    enum LocationChoice: Equatable, Hashable {
        case any
        case unassigned
        case location(String) // location id
    }

    /// Discogs sync facet: any, only synced, or only not-yet-synced records.
    enum SyncStatus: Equatable {
        case any
        case synced
        case notSynced
    }

    var location: LocationChoice = .any
    var genre: String?
    var format: String?
    var mediaCondition: Condition?
    /// Minimum star rating; 0 means "any".
    var minRating: Int = 0
    var sync: SyncStatus = .any

    var isActive: Bool {
        location != .any || genre != nil || format != nil || mediaCondition != nil || minRating > 0 || sync != .any
    }

    /// How many facets are set — shown as a badge on the Filter control.
    var activeCount: Int {
        var count = 0
        if location != .any { count += 1 }
        if genre != nil { count += 1 }
        if format != nil { count += 1 }
        if mediaCondition != nil { count += 1 }
        if minRating > 0 { count += 1 }
        if sync != .any { count += 1 }
        return count
    }

    func matches(_ release: Release) -> Bool {
        switch location {
        case .any:
            break
        case .unassigned:
            if release.locationID != nil { return false }
        case let .location(id):
            if release.locationID != id { return false }
        }
        if let genre, release.genre != genre { return false }
        if let format, release.format != format { return false }
        if let mediaCondition, release.mediaCondition != mediaCondition { return false }
        if minRating > 0, release.rating < minRating { return false }
        switch sync {
        case .any: break
        case .synced: if release.discogsSyncedAt == nil { return false }
        case .notSynced: if release.discogsSyncedAt != nil { return false }
        }
        return true
    }
}
