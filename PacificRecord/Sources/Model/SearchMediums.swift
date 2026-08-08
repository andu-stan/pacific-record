import Foundation
import VinylCore

/// Which media the user wants online searches to return, persisted in
/// `UserDefaults` so both the settings screen (`@AppStorage`) and the search
/// code can reach it.
enum SearchMediums {
    static let storageKey = "searchMediums"

    /// The stored selection, or vinyl-only if the user has never touched it —
    /// this is a record collection app. An explicitly emptied list means "don't
    /// filter", which is what `MediumFilter` does with an empty set.
    static var current: MediumFilter {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return .default }
        return MediumFilter(storageValue: raw)
    }
}
