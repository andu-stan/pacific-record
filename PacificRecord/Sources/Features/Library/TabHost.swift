import SwiftUI
import VinylCore

/// The app shell. Library is always present; Stats and Wishlist are optional
/// and switched on in Settings, so the tab bar only appears when at least one
/// of them is enabled — a single-tab bar would be pure chrome.
struct TabHost: View {
    @AppStorage(WishlistModel.showStatsKey) private var showStats = true
    @AppStorage(WishlistModel.showWishlistKey) private var showWishlist = false
    @State private var tab: AppTab = .library

    enum AppTab: String, CaseIterable, Identifiable {
        case library, stats, wishlist
        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: return "Library"
            case .stats: return "Stats"
            case .wishlist: return "Wishlist"
            }
        }

        var icon: String {
            switch self {
            case .library: return "square.grid.2x2"
            case .stats: return "chart.bar"
            case .wishlist: return "heart"
            }
        }
    }

    private var tabs: [AppTab] {
        var result: [AppTab] = [.library]
        if showStats { result.append(.stats) }
        if showWishlist { result.append(.wishlist) }
        return result
    }

    var body: some View {
        Group {
            if tabs.count > 1 {
                VStack(spacing: 0) {
                    screen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    TabBar(tabs: tabs, selection: $tab)
                }
                .background(Palette.background)
            } else {
                LibraryView()
            }
        }
        // If the visible tab gets switched off in Settings, fall back.
        .onChange(of: tabs) { _, current in
            if !current.contains(tab) { tab = .library }
        }
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .library:
            LibraryView()
        case .stats:
            NavigationStack { StatsView() }.tint(Palette.tint)
        case .wishlist:
            NavigationStack { WishlistView() }.tint(Palette.tint)
        }
    }
}

/// 56pt of chrome with a hairline top edge; icon over an overline label.
struct TabBar: View {
    let tabs: [TabHost.AppTab]
    @Binding var selection: TabHost.AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                    Haptics.impact()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? "\(tab.icon).fill" : tab.icon)
                            .font(.system(size: 17, weight: .regular))
                        Text(tab.title.uppercased())
                            .font(.prCaption)
                            .tracking(Metrics.overlineTracking)
                    }
                    .foregroundStyle(selection == tab ? Palette.accent : Palette.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background {
            Rectangle().fill(Palette.chrome).ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.separator).frame(height: 1) }
    }
}
