import Foundation

/// Shared fuzzy matching for artwork lookups (Apple Music, Deezer).
///
/// Search APIs happily return *something* for any query, so the danger isn't
/// finding nothing — it's confidently substituting the wrong cover. Everything
/// here exists to answer one question: is this result really the record we
/// asked for? A result must match on **title** to be considered at all; a
/// matching artist alone is never enough (otherwise a search for Metallica's
/// "…And Justice for All" happily returns the cover of any other Metallica
/// album).
public enum ArtworkMatching {
    /// Bracketed/trailing qualifiers that don't change *which* album it is, so
    /// "…And Justice for All (Remastered)" still matches "...And Justice for All".
    ///
    /// Deliberately excludes "live": it genuinely distinguishes a record, and
    /// dropping it would let a live album borrow the studio album's cover.
    private static let editionKeywords: Set<String> = [
        "remaster", "remastered", "remastering", "remix", "remixes", "mix",
        "deluxe", "expanded", "anniversary", "edition", "version", "mono",
        "stereo", "explicit", "clean", "bonus", "reissue", "special", "super",
        "collector", "collectors", "legacy", "digital", "single", "ep", "lp",
        "album", "original", "soundtrack", "box", "boxed", "extended",
        "definitive", "ultimate", "complete", "japanese", "import", "vinyl",
        "master", "mastered", "motion", "picture",
    ]

    /// A title/artist reduced to a comparable form: diacritics folded, edition
    /// qualifiers removed, "&" spelled out, everything else stripped to
    /// alphanumerics. "…And Justice for All (Remastered)" → "andjusticeforall".
    public static func normalize(_ text: String) -> String {
        var working = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        working = strippingBracketedQualifiers(working)
        working = strippingTrailingQualifier(working)
        working = working.replacingOccurrences(of: "&", with: " and ")
        var result = ""
        for scalar in working.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// 0…1 similarity between two normalized strings: edit-distance ratio, or
    /// the length ratio when one fully contains the other (an untagged suffix).
    public static func similarity(_ first: String, _ second: String) -> Double {
        if first.isEmpty || second.isEmpty { return 0 }
        if first == second { return 1 }

        let a = Array(first), b = Array(second)
        let longest = Double(max(a.count, b.count))
        let ratio = 1 - Double(levenshtein(a, b)) / longest

        var containment = 0.0
        if min(a.count, b.count) >= 6, first.contains(second) || second.contains(first) {
            containment = Double(min(a.count, b.count)) / longest
        }
        return max(ratio, containment)
    }

    /// The best genuine match, or nil when nothing is close enough. Ranked by
    /// title first (it's the discriminating field), artist as a tiebreak.
    public static func bestMatch<Item>(
        in items: [Item],
        title wantedTitle: String,
        artist wantedArtist: String,
        minimumTitleSimilarity: Double = 0.82,
        minimumArtistSimilarity: Double = 0.55,
        titleOf: (Item) -> String,
        artistOf: (Item) -> String
    ) -> Item? {
        let wantTitle = normalize(wantedTitle)
        // Without a title there is nothing to discriminate on, and matching on
        // artist alone is exactly how the wrong cover gets picked.
        guard !wantTitle.isEmpty else { return nil }
        let wantArtist = normalize(wantedArtist)

        var best: (item: Item, score: Double)?
        for item in items {
            let titleSimilarity = similarity(wantTitle, normalize(titleOf(item)))
            guard titleSimilarity >= minimumTitleSimilarity else { continue }

            var artistSimilarity = 1.0
            if !wantArtist.isEmpty {
                artistSimilarity = similarity(wantArtist, normalize(artistOf(item)))
                guard artistSimilarity >= minimumArtistSimilarity else { continue }
            }

            let score = titleSimilarity * 0.65 + artistSimilarity * 0.35
            if score > (best?.score ?? 0) { best = (item, score) }
        }
        return best?.item
    }

    // MARK: - Internals

    /// Drops "(…)" / "[…]" groups that read as an edition tag.
    static func strippingBracketedQualifiers(_ text: String) -> String {
        var result = ""
        var buffer = ""
        var inGroup = false
        for character in text {
            switch character {
            case "(", "[":
                if inGroup { buffer.append(character) } else { inGroup = true; buffer = "" }
            case ")", "]":
                if inGroup {
                    inGroup = false
                    // A bracketed group is nearly always an edition tag, so one
                    // keyword is enough to drop it ("(Super Deluxe)").
                    if !containsEditionKeyword(buffer) { result += " " + buffer + " " }
                } else {
                    result.append(character)
                }
            default:
                if inGroup { buffer.append(character) } else { result.append(character) }
            }
        }
        if inGroup { result += " " + buffer }   // unbalanced bracket
        return result
    }

    /// Drops a trailing " - Remastered" / " - Single" style qualifier (iTunes
    /// formats them this way rather than in brackets).
    static func strippingTrailingQualifier(_ text: String) -> String {
        guard let range = text.range(of: " - ", options: .backwards) else { return text }
        let tail = String(text[range.upperBound...])
        return isEditionQualifier(tail) ? String(text[..<range.lowerBound]) : text
    }

    /// True when *every* word is an edition keyword, a year, or noise — the
    /// stricter rule, used for a trailing " - …" where real title words can live.
    static func isEditionQualifier(_ text: String) -> Bool {
        let parts = words(in: text)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { word in
            editionKeywords.contains(word) || Int(word) != nil || word.count <= 2
        }
    }

    /// True when *any* word is an edition keyword — the looser rule for
    /// bracketed groups.
    static func containsEditionKeyword(_ text: String) -> Bool {
        words(in: text).contains { editionKeywords.contains($0) }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { character in
                !character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            })
            .map(String.init)
    }

    /// Classic two-row Levenshtein; the strings here are short album titles.
    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
