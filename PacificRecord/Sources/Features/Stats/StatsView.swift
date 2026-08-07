import SwiftUI
import VinylCore

/// "Collection" — genre split, additions over the last year, and the most
/// collected artists. All derived from the library; nothing is stored.
struct StatsView: View {
    @Environment(LibraryModel.self) private var model

    /// Chart series always run primary-500 → 400 → 300 → 200, with the
    /// deliberately desaturated neutral carrying "Other".
    private static let series: [Color] = [
        Palette.primary500, Palette.primary400, Palette.primary300, Palette.primary200,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Collection")
                    .font(.prDisplay)
                    .tracking(-0.8)
                    .foregroundStyle(Palette.label)
                    .padding(.bottom, 4)

                genresCard
                addedCard
                artistsCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .refreshable { model.refreshAll() }
    }

    // MARK: Genres

    /// Top four genres by count, everything else folded into "Other".
    private var genreBuckets: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in model.records {
            let genre = record.genre?.trimmingCharacters(in: .whitespaces)
            counts[(genre?.isEmpty == false ? genre! : "Unknown"), default: 0] += 1
        }
        let sorted = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        var buckets = sorted.prefix(4).map { (name: $0.key, count: $0.value) }
        let remainder = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        if remainder > 0 { buckets.append((name: "Other", count: remainder)) }
        return buckets
    }

    private var genresCard: some View {
        StatsCard(title: "Genres", trailing: "\(model.records.count) records") {
            let buckets = genreBuckets
            if buckets.isEmpty {
                emptyNote("No genres recorded yet.")
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    // A single stacked bar: proportion at a glance, no axis.
                    HStack(spacing: 4) {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                                .fill(color(at: index, of: buckets.count))
                                .frame(height: 28)
                                .layoutPriority(Double(bucket.count))
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              spacing: 12) {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                                    .fill(color(at: index, of: buckets.count))
                                    .frame(width: 10, height: 10)
                                Text("\(bucket.name) · \(bucket.count)")
                                    .font(.prCaptionSm)
                                    .foregroundStyle(Palette.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(at index: Int, of total: Int) -> Color {
        // The last bucket is "Other" when it overflowed the top four.
        if index >= Self.series.count { return Palette.neutral }
        if total > Self.series.count, index == total - 1 { return Palette.neutral }
        return Self.series[index]
    }

    // MARK: Added

    /// Counts per month for the last twelve months, oldest first.
    private var addedByMonth: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [(String, Int)] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMMM"   // narrow month initial
        for offset in stride(from: 11, through: 0, by: -1) {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let range = calendar.dateInterval(of: .month, for: month)
            let count = model.records.filter { range?.contains($0.addedAt) ?? false }.count
            buckets.append((formatter.string(from: month), count))
        }
        return buckets
    }

    private var addedCard: some View {
        let months = addedByMonth
        let total = months.reduce(0) { $0 + $1.count }
        let peak = max(1, months.map(\.count).max() ?? 1)
        return StatsCard(title: "Added this year", trailing: "\(total) records") {
            // Dots scaled by value — the design's activity row.
            HStack(alignment: .center, spacing: 10) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Palette.primary500)
                            .opacity(month.count == 0 ? 0.18 : 0.35 + 0.65 * Double(month.count) / Double(peak))
                            .frame(width: dotSize(month.count, peak: peak),
                                   height: dotSize(month.count, peak: peak))
                            .frame(height: 16)
                        Text(month.label)
                            .font(.prMonoTiny)
                            .foregroundStyle(Palette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dotSize(_ count: Int, peak: Int) -> CGFloat {
        guard count > 0 else { return 4 }
        return 4 + 12 * CGFloat(count) / CGFloat(peak)
    }

    // MARK: Artists

    private var topArtists: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in model.records where !record.artistDisplay.isEmpty {
            counts[record.artistDisplay, default: 0] += 1
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(5)
            .map { (name: $0.key, count: $0.value) }
    }

    private var artistsCard: some View {
        let artists = topArtists
        let peak = max(1, artists.first?.count ?? 1)
        return StatsCard(title: "Most collected", trailing: nil) {
            if artists.isEmpty {
                emptyNote("Add a few records to see this.")
            } else {
                VStack(spacing: 16) {
                    ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(artist.name)
                                    .font(.prBody)
                                    .foregroundStyle(Palette.label)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(artist.count)")
                                    .font(.prNumeric)
                                    .foregroundStyle(Palette.tertiary)
                            }
                            // 6pt progress bar, primary fill on a faint track.
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.fill)
                                    Capsule().fill(Palette.primary500)
                                        .frame(width: geometry.size.width * CGFloat(artist.count) / CGFloat(peak))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.prSmall)
            .foregroundStyle(Palette.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section container: title row on one baseline, then content.
struct StatsCard<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.prHeadline).foregroundStyle(Palette.label)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.prCaptionSm).foregroundStyle(Palette.secondary)
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.grouped, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}
