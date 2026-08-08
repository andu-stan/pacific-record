import Foundation

/// A physical medium a release can be issued on. Discogs names dozens of
/// formats; this is the short vocabulary the app offers as a search filter.
/// Anything outside it counts as "unknown" rather than "no match", so an
/// unusual pressing is never silently hidden.
public enum ReleaseMedium: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case vinyl
    case shellac
    case cd
    case sacd
    case cassette
    case eightTrack
    case reelToReel
    case minidisc
    case dvd
    case bluRay
    case file

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .shellac: return "Shellac (78s)"
        case .cd: return "CD"
        case .sacd: return "SACD"
        case .cassette: return "Cassette"
        case .eightTrack: return "8-Track"
        case .reelToReel: return "Reel-to-reel"
        case .minidisc: return "MiniDisc"
        case .dvd: return "DVD"
        case .bluRay: return "Blu-ray"
        case .file: return "Digital file"
        }
    }

    /// The value Discogs' `format` search parameter expects for this medium.
    public var discogsFormatName: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .shellac: return "Shellac"
        case .cd: return "CD"
        case .sacd: return "SACD"
        case .cassette: return "Cassette"
        case .eightTrack: return "8-Track Cartridge"
        case .reelToReel: return "Reel-To-Reel"
        case .minidisc: return "Minidisc"
        case .dvd: return "DVD"
        case .bluRay: return "Blu-ray"
        case .file: return "File"
        }
    }

    /// Recognises a medium from the name a source uses — Discogs' format names
    /// ("Vinyl", "CDr", "8-Track Cartridge") and MusicBrainz's qualified ones
    /// (`12" Vinyl`, "Digital Media"). Returns nil for anything unrecognised.
    public static func named(_ raw: String) -> ReleaseMedium? {
        let key = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty else { return nil }
        if let exact = exactNames[key] { return exact }
        // Sources qualify the medium (`12" Vinyl`, "8cm CD"), so fall back to a
        // substring pass. Ordered so "SACD" is never read as a plain "CD".
        for (token, medium) in looseTokens where key.contains(token) {
            return medium
        }
        return nil
    }

    private static let exactNames: [String: ReleaseMedium] = [
        "vinyl": .vinyl, "acetate": .vinyl, "flexidisc": .vinyl, "lathecut": .vinyl,
        "shellac": .shellac, "pathedisc": .shellac, "edisondisc": .shellac,
        "cd": .cd, "cdr": .cd, "cdv": .cd,
        "sacd": .sacd,
        "cassette": .cassette, "microcassette": .cassette, "dcc": .cassette,
        "ntcassette": .cassette, "elcaset": .cassette,
        "8trackcartridge": .eightTrack, "4trackcartridge": .eightTrack, "8track": .eightTrack,
        "reeltoreel": .reelToReel,
        "minidisc": .minidisc,
        "dvd": .dvd, "dvdr": .dvd,
        "bluray": .bluRay, "blurayr": .bluRay, "hddvd": .bluRay, "hddvdr": .bluRay,
        "file": .file, "digitalmedia": .file, "memorystick": .file,
    ]

    private static let looseTokens: [(String, ReleaseMedium)] = [
        ("reeltoreel", .reelToReel),
        ("minidisc", .minidisc),
        ("cassette", .cassette),
        ("shellac", .shellac),
        ("bluray", .bluRay),
        ("8track", .eightTrack),
        ("vinyl", .vinyl),
        ("sacd", .sacd),
        ("dvd", .dvd),
        ("cd", .cd),
    ]
}

/// The media a search should return. Kept as a set so a collector who buys both
/// vinyl and cassettes sees both, and stored as a flat string so it fits in
/// `UserDefaults`/`@AppStorage`.
public struct MediumFilter: Sendable, Equatable {
    public var selected: Set<ReleaseMedium>

    /// A record collection app: vinyl only until the user says otherwise.
    public static let `default` = MediumFilter(selected: [.vinyl])

    /// No filtering at all.
    public static let all = MediumFilter(selected: [])

    public init(selected: Set<ReleaseMedium>) {
        self.selected = selected
    }

    /// Parses the stored form. Unrecognised entries are ignored, so removing a
    /// medium from the vocabulary can't leave a user stuck with an empty list.
    public init(storageValue: String) {
        selected = Set(storageValue.split(separator: ",").compactMap { ReleaseMedium(rawValue: String($0)) })
    }

    /// A stable, order-independent string for `@AppStorage`.
    public var storageValue: String {
        ReleaseMedium.allCases.filter(selected.contains).map(\.rawValue).joined(separator: ",")
    }

    /// True when nothing gets filtered out — no selection (the user unticked
    /// everything) or all of them.
    public var isUnrestricted: Bool {
        selected.isEmpty || selected.count == ReleaseMedium.allCases.count
    }

    /// Keeps a release issued on one of the selected media — or one whose medium
    /// the source didn't name, since dropping unlabelled results would hide good
    /// matches for no gain.
    public func matches(_ match: MetadataMatch) -> Bool {
        matches(mediums: match.mediums)
    }

    public func matches(mediums: [String]) -> Bool {
        guard !isUnrestricted else { return true }
        let known = Set(mediums.compactMap(ReleaseMedium.named))
        guard !known.isEmpty else { return true }
        return !known.isDisjoint(with: selected)
    }

    public func apply(to candidates: [MetadataMatch]) -> [MetadataMatch] {
        guard !isUnrestricted else { return candidates }
        return candidates.filter { matches($0) }
    }

    /// The value for Discogs' `format` search parameter when the selection is a
    /// single medium, so the API narrows the page instead of us throwing most of
    /// it away. Nil when the selection can't be expressed as one value.
    public var discogsSearchFormat: String? {
        guard selected.count == 1, let only = selected.first else { return nil }
        return only.discogsFormatName
    }

    /// Short summary for a settings row, where there's only one line: "All",
    /// "Vinyl", "Vinyl and CD", "4 media".
    public var summary: String {
        let names = selectedNames
        switch names.count {
        case 0, ReleaseMedium.allCases.count: return "All"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) media"
        }
    }

    /// Every selected medium spelled out — "Vinyl, CD and Cassette" — for
    /// explanatory copy that has room for it.
    public var selectedNamesSentence: String {
        let names = selectedNames
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// Display names in the vocabulary's own order, so the summary is stable
    /// however the set was built.
    private var selectedNames: [String] {
        ReleaseMedium.allCases.filter(selected.contains).map(\.displayName)
    }
}
