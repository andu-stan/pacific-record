import Foundation
import VinylCore

/// User-selectable cover-art sources, in the default fallback order.
enum CoverSource: String, CaseIterable, Identifiable {
    case appleMusic
    case deezer
    case coverArtArchive
    case discogs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .deezer: return "Deezer"
        case .coverArtArchive: return "Cover Art Archive"
        case .discogs: return "Discogs"
        }
    }

    static let storageKey = "coverSource"

    static var preferred: CoverSource {
        CoverSource(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .appleMusic
    }
}

/// A cover option surfaced during a manual pick. `url` is the full-size image to
/// download; `thumbURL` is an optional lighter image for the grid (falls back to
/// `url`), so showing many covers at once stays cheap.
struct CoverCandidate: Identifiable, Hashable {
    let source: CoverSource
    let url: URL
    var thumbURL: URL? = nil
    var id: String { url.absoluteString }
}

/// Chooses the best cover URL, trying the user's preferred source first and
/// falling back through the others until one yields an image. Apple Music and
/// Deezer carry the official high-resolution artwork; Cover Art Archive and
/// Discogs cover more pressings (Discogs images are user scans).
enum CoverArtResolver {
    /// UserDefaults key: when true, the import flow lets you pick the cover.
    static let pickCoverOnImportKey = "pickCoverOnImport"

    static func bestURL(
        artist: String,
        title: String,
        barcode: String? = nil,
        musicbrainzMBID: String? = nil,
        discogsFallback: URL? = nil
    ) async -> URL? {
        // Preference order, stopping at the first source with a real match —
        // the common case costs a single request.
        for source in orderedSources() {
            switch source {
            case .appleMusic:
                if let url = await appleURL(artist: artist, title: title) { return url }
            case .deezer:
                if let url = await deezerURL(artist: artist, title: title) { return url }
            case .coverArtArchive:
                if let url = await archiveURL(barcode: barcode, musicbrainzMBID: musicbrainzMBID,
                                              artist: artist, title: title) { return url }
            case .discogs:
                if let discogsFallback { return discogsFallback }
            }
        }
        return discogsFallback
    }

    /// Every cover available for this record, ordered with the preferred source
    /// first — for the manual cover picker. Apple and Deezer contribute their
    /// one official cover each, Cover Art Archive its front image, and Discogs
    /// *all* of the release's images (front, back, labels…).
    ///
    /// The four lookups run concurrently: they hit unrelated services, and doing
    /// them in sequence made opening the picker needlessly slow (each service
    /// has its own rate limiter).
    static func candidates(
        artist: String,
        title: String,
        barcode: String? = nil,
        musicbrainzMBID: String? = nil,
        discogsReleaseID: Int? = nil,
        discogsFallback: URL? = nil
    ) async -> [CoverCandidate] {
        async let apple = appleURL(artist: artist, title: title)
        async let deezer = deezerURL(artist: artist, title: title)
        async let archive = archiveURL(barcode: barcode, musicbrainzMBID: musicbrainzMBID,
                                       artist: artist, title: title)
        async let discogs = discogsCandidates(releaseID: discogsReleaseID, fallback: discogsFallback)

        let (appleResult, deezerResult, archiveResult, discogsResult) =
            await (apple, deezer, archive, discogs)

        var found: [CoverCandidate] = []
        if let appleResult { found.append(CoverCandidate(source: .appleMusic, url: appleResult)) }
        if let deezerResult { found.append(CoverCandidate(source: .deezer, url: deezerResult)) }
        if let archiveResult { found.append(CoverCandidate(source: .coverArtArchive, url: archiveResult)) }
        found.append(contentsOf: discogsResult)

        // Group by preferred source order, keeping each source's own order
        // (so the Discogs primary/front stays first among its images).
        let order = orderedSources()
        return order.flatMap { source in found.filter { $0.source == source } }
    }

    // MARK: - Per-source lookups

    private static func appleURL(artist: String, title: String) async -> URL? {
        (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil
    }

    private static func deezerURL(artist: String, title: String) async -> URL? {
        (try? await DeezerArtworkClient().artworkURL(artist: artist, title: title)) ?? nil
    }

    private static func archiveURL(
        barcode: String?, musicbrainzMBID: String?, artist: String, title: String
    ) async -> URL? {
        let mbid: String?
        if let musicbrainzMBID {
            mbid = musicbrainzMBID
        } else {
            mbid = await resolveMBID(barcode: barcode, artist: artist, title: title)
        }
        guard let mbid else { return nil }
        return (try? await CoverArtArchiveClient().frontCoverURL(mbid: mbid)) ?? nil
    }

    /// Every image on the Discogs release, or the single known cover URL when
    /// there's no release id to expand.
    private static func discogsCandidates(releaseID: Int?, fallback: URL?) async -> [CoverCandidate] {
        if let releaseID {
            let token = DiscogsTokenStore.read()
            if let images = try? await DiscogsClient(token: token).images(releaseID: releaseID), !images.isEmpty {
                return images.map {
                    CoverCandidate(source: .discogs, url: $0.full, thumbURL: $0.thumbnail)
                }
            }
        }
        if let fallback { return [CoverCandidate(source: .discogs, url: fallback)] }
        return []
    }

    /// Preferred source first, then the remaining sources in default order.
    private static func orderedSources() -> [CoverSource] {
        let preferred = CoverSource.preferred
        return [preferred] + CoverSource.allCases.filter { $0 != preferred }
    }

    /// Finds a MusicBrainz release MBID (for the Cover Art Archive) via barcode,
    /// then artist + title.
    private static func resolveMBID(barcode: String?, artist: String, title: String) async -> String? {
        let client = MusicBrainzClient()
        if let barcode, !barcode.isEmpty,
           let results = try? await client.searchByBarcode(barcode),
           let mbid = results.first?.musicbrainzMBID {
            return mbid
        }
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        if !query.isEmpty,
           let results = try? await client.searchByText(query),
           let mbid = results.first?.musicbrainzMBID {
            return mbid
        }
        return nil
    }
}
