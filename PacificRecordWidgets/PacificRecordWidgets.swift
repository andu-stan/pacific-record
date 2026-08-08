import SwiftUI
import WidgetKit

// MARK: - Bundle

@main
struct PacificRecordWidgets: WidgetBundle {
    var body: some Widget {
        RecordOfTheDayWidget()
        LibraryStatsWidget()
    }
}

// MARK: - Timeline

struct LibraryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Which day of the rotation this entry represents.
    let dayOffset: Int

    var record: WidgetRecord? { snapshot.record(forDayOffset: dayOffset, from: date) }
}

/// Reads the shared snapshot and lays out one entry per day, so the record
/// rotates at midnight without the app having to run.
struct LibraryProvider: TimelineProvider {
    private static let daysAhead = 7

    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: Date(), snapshot: .preview, dayOffset: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? (context.isPreview ? .preview : .empty)
        completion(LibraryEntry(date: Date(), snapshot: snapshot, dayOffset: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        let snapshot = WidgetShared.loadSnapshot() ?? .empty
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        var entries: [LibraryEntry] = []
        for offset in 0..<Self.daysAhead {
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            // The first entry must be dated now, or the widget shows nothing
            // until midnight.
            entries.append(LibraryEntry(date: offset == 0 ? Date() : date,
                                        snapshot: snapshot,
                                        dayOffset: offset))
        }
        // Ask for a refresh once the week of entries runs out.
        let refresh = calendar.date(byAdding: .day, value: Self.daysAhead, to: startOfToday) ?? Date()
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Record of the day

struct RecordOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecordOfTheDay", provider: LibraryProvider()) { entry in
            RecordOfTheDayView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Record of the Day")
        .description("A different record from your collection each day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecordOfTheDayView: View {
    let entry: LibraryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let record = entry.record {
                switch family {
                case .systemMedium: medium(record)
                default: small(record)
                }
            } else {
                WidgetEmptyView(message: entry.snapshot.recordCount == 0
                                ? "Add a record to get started"
                                : "Open Pacific Record to sync")
            }
        }
        .widgetURL(entry.record.flatMap { WidgetDeepLink.record($0.id) } ?? WidgetDeepLink.library)
    }

    /// Small: the sleeve is the widget, with the title over a scrim.
    private func small(_ record: WidgetRecord) -> some View {
        ZStack(alignment: .bottomLeading) {
            WidgetCover(fileName: record.coverFile, seed: record.title)
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(record.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(10)
        }
    }

    /// Medium: sleeve beside the details.
    private func medium(_ record: WidgetRecord) -> some View {
        HStack(spacing: 14) {
            WidgetCover(fileName: record.coverFile, seed: record.title)
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Record of the day".uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(WidgetPalette.accent)
                Text(record.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetPalette.label)
                    .lineLimit(2)
                Text(record.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                if !record.detailLine.isEmpty {
                    Text(record.detailLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WidgetPalette.tertiary)
                }
                if record.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<record.rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(WidgetPalette.accent)
                        }
                    }
                    .padding(.top, 1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Library stats

struct LibraryStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LibraryStats", provider: LibraryProvider()) { entry in
            LibraryStatsView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Library Stats")
        .description("Records, artists and estimated value at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LibraryStatsView: View {
    let entry: LibraryEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if snapshot.recordCount == 0 {
                WidgetEmptyView(message: "No records yet")
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .widgetURL(WidgetDeepLink.stats)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.libraryName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(WidgetPalette.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(snapshot.recordCount)")
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.label)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Records".uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(WidgetPalette.tertiary)
            Spacer(minLength: 0)
            if let value = snapshot.formattedValue {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.libraryName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetPalette.label)
                .lineLimit(1)

            HStack(spacing: 0) {
                statBlock(value: "\(snapshot.recordCount)", label: "Records")
                statBlock(value: "\(snapshot.artistCount)", label: "Artists")
                statBlock(value: "\(snapshot.genreCount)", label: "Genres")
            }

            if let value = snapshot.formattedValue {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.accent)
                    Text("· \(snapshot.valuedCount) priced")
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetPalette.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.label)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(WidgetPalette.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

/// The cover from the shared container, or a deterministic gradient when the
/// record has no artwork.
struct WidgetCover: View {
    let fileName: String?
    let seed: String

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                LinearGradient(colors: gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var image: UIImage? {
        guard let fileName, let url = WidgetShared.coverURL(named: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Same idea as the app's placeholder: stable colours derived from the title.
    private var gradientColors: [Color] {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) ^ UInt64(byte) }
        let palettes: [[Color]] = [
            [Color(red: 0.42, green: 0.39, blue: 0.91), Color(red: 0.16, green: 0.11, blue: 0.82)],
            [Color(red: 0.30, green: 0.25, blue: 0.75), Color(red: 0.10, green: 0.08, blue: 0.45)],
            [Color(red: 0.56, green: 0.53, blue: 0.93), Color(red: 0.29, green: 0.24, blue: 0.91)],
        ]
        return palettes[Int(hash % UInt64(palettes.count))]
    }
}

struct WidgetEmptyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(WidgetPalette.tertiary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The design system's tokens, restated here so the extension doesn't have to
/// pull in the app's whole design layer.
enum WidgetPalette {
    static let accent = Color(red: 0.42, green: 0.39, blue: 0.91)      // primary-500
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.055, blue: 0.055, alpha: 1)  // canvas #0E0E0E
            : .white
    })
    static let label = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.067, green: 0.071, blue: 0.078, alpha: 1)
    })
    static let secondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.706, alpha: 1)
            : UIColor(red: 0.353, green: 0.369, blue: 0.400, alpha: 1)
    })
    static let tertiary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.486, alpha: 1)
            : UIColor(red: 0.541, green: 0.561, blue: 0.596, alpha: 1)
    })
}

// MARK: - Previews

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        generatedAt: Date(),
        libraryName: "Pacific Record",
        recordCount: 248,
        artistCount: 96,
        genreCount: 7,
        formattedValue: "$4,312.50",
        valuedCount: 180,
        records: [
            WidgetRecord(id: "1", title: "Kind of Blue", artist: "Miles Davis",
                         year: 1959, format: "LP", rating: 5, coverFile: nil),
        ]
    )
}
