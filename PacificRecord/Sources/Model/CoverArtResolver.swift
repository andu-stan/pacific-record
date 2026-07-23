import Foundation
import VinylCore

/// Chooses the best cover URL for a record: Apple Music's official high-res
/// artwork when it confidently matches, otherwise the provided fallback
/// (usually the Discogs image).
enum CoverArtResolver {
    static func bestURL(artist: String, title: String, fallback: URL?) async -> URL? {
        if let apple = (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil {
            return apple
        }
        return fallback
    }
}
