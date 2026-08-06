import Foundation
import VinylCore

extension Release {
    /// Seed for the placeholder cover gradient.
    var coverSeed: String { title }

    /// Cover to draw in lists and grids: the small on-disk thumbnail when we
    /// have one, so browsing never decodes a full-resolution scan.
    var listCoverPath: String? { thumbPath ?? coverPath }

    /// "$42.00" when the record has been valued, else nil.
    var formattedValue: String? {
        guard let amount = estimatedValue, let currency = valueCurrency else { return nil }
        return amount.formatted(.currency(code: currency))
    }

    /// "Artist · 1959" for list rows.
    var listSubtitle: String {
        if let year { return "\(artistDisplay) · \(year)" }
        return artistDisplay
    }

    /// "LP · 33⅓ RPM" for the detail info card.
    var formatLine: String {
        var parts: [String] = []
        if let format { parts.append(format) }
        if let speed { parts.append("\(speed) RPM") }
        return parts.joined(separator: " · ")
    }

    /// "1959 · US" for the detail info card.
    var yearCountryLine: String {
        [year.map(String.init), country].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Jazz · Modal" for the detail info card.
    var genreLine: String {
        ([genre].compactMap { $0 } + styles).joined(separator: " · ")
    }
}

extension Track {
    /// "9:22" from a duration in seconds.
    var durationText: String {
        guard let seconds = durationSeconds else { return "" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
