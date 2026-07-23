import Foundation
import VinylCore

/// User-selectable cover-art sources, in the default fallback order.
enum CoverSource: String, CaseIterable, Identifiable {
    case appleMusic
    case coverArtArchive
    case discogs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
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
/// falling back through the others until one yields an image. Apple Music is
/// the official high-res artwork; Cover Art Archive and Discogs cover more
/// pressings.
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
        for source in orderedSources() {
            switch source {
            case .appleMusic:
                if let url = (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil {
                    return url
                }
            case .coverArtArchive:
                let mbid: String?
                if let known = musicbrainzMBID {
                    mbid = known
                } else {
                    mbid = await resolveMBID(barcode: barcode, artist: artist, title: title)
                }
                if let mbid, let url = (try? await CoverArtArchiveClient().frontCoverURL(mbid: mbid)) ?? nil {
                    return url
                }
            case .discogs:
                if let discogsFallback { return discogsFallback }
            }
        }
        return discogsFallback
    }

    /// Every cover available for this record, ordered with the preferred source
    /// first — for the manual cover picker. Apple and Cover Art Archive each
    /// contribute one image; Discogs contributes *all* of the release's images
    /// (front, back, labels…) when a `discogsReleaseID` is known.
    static func candidates(
        artist: String,
        title: String,
        barcode: String? = nil,
        musicbrainzMBID: String? = nil,
        discogsReleaseID: Int? = nil,
        discogsFallback: URL? = nil
    ) async -> [CoverCandidate] {
        var found: [CoverCandidate] = []

        if let apple = (try? await AppleArtworkClient().artworkURL(artist: artist, title: title)) ?? nil {
            found.append(CoverCandidate(source: .appleMusic, url: apple))
        }

        let mbid: String?
        if let known = musicbrainzMBID {
            mbid = known
        } else {
            mbid = await resolveMBID(barcode: barcode, artist: artist, title: title)
        }
        if let mbid, let caa = (try? await CoverArtArchiveClient().frontCoverURL(mbid: mbid)) ?? nil {
            found.append(CoverCandidate(source: .coverArtArchive, url: caa))
        }

        // Discogs: pull every image for the release, not just the primary.
        var discogsCovers: [CoverCandidate] = []
        if let discogsReleaseID {
            let token = UserDefaults.standard.string(forKey: "discogsToken") ?? ""
            if let images = try? await DiscogsClient(token: token).images(releaseID: discogsReleaseID) {
                discogsCovers = images.map {
                    CoverCandidate(source: .discogs, url: $0.full, thumbURL: $0.thumbnail)
                }
            }
        }
        // Fall back to the single known Discogs URL if the lookup found nothing.
        if discogsCovers.isEmpty, let discogsFallback {
            discogsCovers = [CoverCandidate(source: .discogs, url: discogsFallback)]
        }
        found.append(contentsOf: discogsCovers)

        // Group by preferred source order, keeping each source's own order
        // (so the Discogs primary/front stays first among its images).
        let order = orderedSources()
        return order.flatMap { source in found.filter { $0.source == source } }
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
