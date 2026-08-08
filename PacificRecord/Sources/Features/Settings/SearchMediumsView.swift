import SwiftUI
import VinylCore

/// Pick the media online searches should return. A vinyl collector doesn't want
/// a page of CD pressings between them and the record they scanned.
struct SearchMediumsView: View {
    @AppStorage(SearchMediums.storageKey) private var storedValue = MediumFilter.default.storageValue

    private var filter: MediumFilter { MediumFilter(storageValue: storedValue) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                GroupedCard() {
                    VStack(spacing: 0) {
                        ForEach(Array(ReleaseMedium.allCases.enumerated()), id: \.element.id) { index, medium in
                            row(medium)
                            if index < ReleaseMedium.allCases.count - 1 { HRule() }
                        }
                    }
                }

                Text(footnote)
                    .font(.prSmall).foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 4)

                Text("Releases whose medium a source doesn't name are always shown, and a barcode scan falls back to every result rather than coming up empty. Your library and Discogs collection imports aren't filtered.")
                    .font(.prSmall).foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 4)

                if !filter.isUnrestricted {
                    // Ticks everything rather than clearing, so the rows agree
                    // with what the app will do. An empty list means the same
                    // thing, but reads as "nothing on".
                    Button { storedValue = MediumFilter(selected: Set(ReleaseMedium.allCases)).storageValue } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 16))
                            Text("Show every medium").font(.prBodyEmphasis)
                            Spacer()
                        }
                        .foregroundStyle(Palette.tint)
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .background(Palette.grouped, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
        }
        .background(Palette.background)
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ medium: ReleaseMedium) -> some View {
        let isOn = filter.selected.contains(medium)
        return Button {
            toggle(medium)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: isOn ? .semibold : .light))
                    .foregroundStyle(isOn ? Palette.accent : Palette.quaternary)
                Text(medium.displayName)
                    .font(.prBody)
                    .foregroundStyle(Palette.label)
                Spacer()
            }
            .frame(minHeight: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ medium: ReleaseMedium) {
        var selected = filter.selected
        if selected.contains(medium) {
            selected.remove(medium)
        } else {
            selected.insert(medium)
        }
        storedValue = MediumFilter(selected: selected).storageValue
    }

    private var footnote: String {
        if filter.selected.isEmpty {
            return "Nothing selected, so searches show every medium."
        }
        if filter.selected.count == ReleaseMedium.allCases.count {
            return "Everything is selected, so nothing is filtered out."
        }
        if filter.selected.count == 1 {
            return "Discogs is asked for \(filter.selectedNamesSentence) directly, so a whole page of results is yours to pick from."
        }
        return "Search results are kept to \(filter.selectedNamesSentence)."
    }
}
