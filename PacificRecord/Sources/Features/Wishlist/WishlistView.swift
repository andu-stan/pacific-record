import SwiftUI
import VinylCore

/// Records you're hunting for, with Discogs price and availability tracking.
struct WishlistView: View {
    @Environment(WishlistModel.self) private var wishlist
    @Environment(LibraryModel.self) private var library
    @AppStorage("discogsToken") private var token = ""

    @State private var showAdd = false
    @State private var confirmDelete: WishlistItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Wishlist")
                        .font(.prDisplay)
                        .tracking(-0.8)
                        .foregroundStyle(Palette.label)
                    Text("Experimental".uppercased())
                        .font(.prBadge)
                        .tracking(Metrics.overlineTracking)
                        .foregroundStyle(Palette.badgeAmberText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.badgeAmberFill, in: Capsule())
                }

                Text(summary)
                    .font(.prCaptionSm)
                    .foregroundStyle(Palette.tertiary)
                    .padding(.top, 6)
                    .padding(.bottom, 16)

                controlStrip

                if wishlist.isRefreshing {
                    ProgressView(value: wishlist.refreshProgress)
                        .tint(Palette.accent)
                        .padding(.bottom, 16)
                }

                if wishlist.visibleItems.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(wishlist.visibleItems) { item in
                            WishlistRow(item: item)
                                .contextMenu {
                                    Button(role: .destructive) { confirmDelete = item } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .refreshable { await wishlist.refreshPrices() }
        .sheet(isPresented: $showAdd) {
            WishlistAddView().environment(wishlist)
        }
        .confirmationDialog(
            confirmDelete.map { "Remove “\($0.title)”?" } ?? "",
            isPresented: Binding(get: { confirmDelete != nil },
                                 set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let item = confirmDelete { wishlist.delete(item) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Button {
                    Task { await wishlist.refreshPrices() }
                } label: {
                    Text("Prices")
                        .font(.prCaption)
                        .tracking(Metrics.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .disabled(wishlist.isRefreshing || token.isEmpty || wishlist.trackedCount == 0)

                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 36, height: 36)
                        .background(Palette.primaryFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to wishlist")
            }
            .padding(4)
            .background(Palette.fill, in: Capsule())
        }
        .frame(height: 48)
        .padding(.bottom, 8)
    }

    private var summary: String {
        let total = wishlist.items.count
        guard total > 0 else { return "Nothing tracked yet" }
        let tracked = wishlist.trackedCount
        var text = total == 1 ? "1 record" : "\(total) records"
        if tracked > 0 { text += " · \(tracked) priced from Discogs" }
        return text
    }

    private var controlStrip: some View {
        @Bindable var wishlist = wishlist
        return HStack(spacing: 8) {
            Button {
                wishlist.inStockOnly.toggle()
            } label: {
                Text("In stock only")
                    .font(.prCaption)
                    .tracking(Metrics.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(wishlist.inStockOnly ? Palette.onPrimary : Palette.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(wishlist.inStockOnly ? Palette.primaryFill : Palette.fill, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("\(wishlist.visibleItems.count) shown")
                .font(.prCaptionSm)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiary)
        }
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(wishlist.items.isEmpty
                 ? "Nothing on the wishlist yet."
                 : "Nothing in stock right now.")
                .font(.prSmall)
                .foregroundStyle(Palette.tertiary)
            if wishlist.items.isEmpty {
                Button { showAdd = true } label: {
                    Text("Add a record")
                        .font(.prCaption)
                        .tracking(Metrics.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Row

struct WishlistRow: View {
    let item: WishlistItem

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.separator).frame(height: 1)
            HStack(spacing: 16) {
                CoverArtView(seed: item.title, coverPath: item.thumbPath,
                             cornerRadius: Metrics.tileRadius, maxPixel: CoverSize.row)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.prSmall)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.isInStock ? Palette.positive : Palette.quaternary)
                            .frame(width: 6, height: 6)
                        Text(item.statusText)
                            .font(.prCaptionSm)
                            .foregroundStyle(Palette.tertiary)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if let price = item.formattedPrice {
                        Text(price)
                            .font(.prNumeric)
                            .foregroundStyle(Palette.label)
                    }
                    if let delta = item.formattedDelta {
                        Text(delta)
                            .font(.prMonoSmall)
                            .foregroundStyle(deltaColor)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// Cheaper is good news, dearer isn't; no movement stays quiet.
    private var deltaColor: Color {
        guard let delta = item.priceDelta, delta != 0 else { return Palette.tertiary }
        return delta < 0 ? Palette.positive : Palette.accentWarm
    }
}

// MARK: - Add

/// Adds to the wishlist by searching Discogs, or by typing it in.
struct WishlistAddView: View {
    @Environment(WishlistModel.self) private var wishlist
    @Environment(\.dismiss) private var dismiss
    @AppStorage("discogsToken") private var token = ""

    @State private var query = ""
    @State private var matches: [MetadataMatch] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var manualTitle = ""
    @State private var manualArtist = ""
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.tertiary)
                        TextField("Artist or album title", text: $query)
                            .font(.prBody)
                            .foregroundStyle(Palette.label)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { search() }
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.grouped, in: Capsule())

                    if let message {
                        Text(message).font(.prSmall).foregroundStyle(Palette.tertiary)
                    }

                    ForEach(matches) { match in
                        Button { add(match) } label: {
                            HStack(spacing: 12) {
                                RemoteCoverView(url: match.coverImageURL, seed: match.title,
                                                cornerRadius: Metrics.tileRadius)
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.title)
                                        .font(.prBodyEmphasis).foregroundStyle(Palette.label).lineLimit(1)
                                    Text([match.artistDisplay, match.year.map(String.init)]
                                            .compactMap { $0 }.joined(separator: " · "))
                                        .font(.prSmall).foregroundStyle(Palette.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Palette.tint)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showManual = true } label: {
                        Text("Add by hand instead")
                            .font(.prCaption)
                            .tracking(Metrics.overlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Palette.background)
            .navigationTitle("Add to wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Add by hand", isPresented: $showManual) {
                TextField("Title", text: $manualTitle)
                TextField("Artist", text: $manualArtist)
                Button("Add") {
                    wishlist.addManual(title: manualTitle, artist: manualArtist, notes: nil)
                    manualTitle = ""; manualArtist = ""
                    Haptics.success()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { manualTitle = ""; manualArtist = "" }
            }
        }
        .tint(Palette.tint)
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        message = nil
        Task {
            let mediums = SearchMediums.current
            let provider: any MetadataProvider = token.isEmpty
                ? MusicBrainzClient()
                : CompositeMetadataProvider(
                    providers: [DiscogsClient(token: token, mediums: mediums), MusicBrainzClient()])
            do {
                let found = try await provider.searchByText(trimmed)
                matches = mediums.apply(to: found)
                if matches.isEmpty {
                    message = found.isEmpty
                        ? "No releases found."
                        : "No releases on the media you search for. Change that in Settings."
                }
            } catch {
                message = AddFlowModel.message(for: error)
            }
            isSearching = false
        }
    }

    private func add(_ match: MetadataMatch) {
        Task {
            let added = await wishlist.add(from: match)
            if added {
                Haptics.success()
                dismiss()
            } else {
                message = "That release is already on your wishlist."
                Haptics.warning()
            }
        }
    }
}
