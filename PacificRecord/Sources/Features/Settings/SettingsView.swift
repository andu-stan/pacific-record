import SwiftUI
import VinylCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LibraryModel.self) private var library
    @AppStorage("discogsToken") private var token = ""
    @AppStorage(CoverSource.storageKey) private var coverSourceRaw = CoverSource.appleMusic.rawValue
    @AppStorage(CoverArtResolver.pickCoverOnImportKey) private var pickCoverOnImport = false
    @AppStorage(DiscogsCollectionSync.autoSyncKey) private var syncToDiscogs = false
    @State private var showTokenEntry = false
    @State private var tokenDraft = ""

    private var isConnected: Bool { !token.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                metadataSection
                coverArtSection
                locationsSection
                storageSection
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
        .alert("Discogs API token", isPresented: $showTokenEntry) {
            TextField("Paste token", text: $tokenDraft)
            Button("Save") { token = tokenDraft.trimmingCharacters(in: .whitespaces); tokenDraft = "" }
            Button("Cancel", role: .cancel) { tokenDraft = "" }
        } message: {
            Text("Create a personal access token at discogs.com/settings/developers.")
        }
    }

    // MARK: Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Metadata")
            GroupedCard(radius: 14) {
                VStack(spacing: 0) {
                    Button { tokenDraft = token; showTokenEntry = true } label: {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Discogs API token").font(.prBody).foregroundStyle(Palette.label)
                                Spacer()
                                Text(isConnected ? "Connected" : "Not connected")
                                    .font(.prFootnote)
                                    .foregroundStyle(isConnected ? Palette.positive : Palette.secondary)
                            }
                            .padding(.vertical, 12)
                            if isConnected {
                                HStack {
                                    Text("••••••••••••" + String(token.suffix(4)))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Palette.tertiary)
                                    Spacer()
                                }
                                .padding(.bottom, 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    HRule()
                    Link(destination: URL(string: "https://www.discogs.com/settings/developers")!) {
                        HStack {
                            Text("Where to find your token").font(.prBody).foregroundStyle(Palette.tint)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.tint)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }

            Text("Without a token, lookups use MusicBrainz. Add one for Discogs' richer pressing data.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)

            GroupedCard(radius: 14) {
                VStack(spacing: 0) {
                    sourceRow(index: 1, name: token.isEmpty ? "MusicBrainz" : "Discogs", divider: true)
                    sourceRow(index: 2, name: token.isEmpty ? "—" : "MusicBrainz", divider: false)
                }
            }

            GroupedCard(radius: 14) {
                HStack {
                    Text("Add new records to Discogs").font(.prBody).foregroundStyle(Palette.label)
                    Spacer()
                    Toggle("", isOn: $syncToDiscogs).labelsHidden().tint(Palette.accent).disabled(token.isEmpty)
                }
                .padding(.vertical, 6)
            }
            Text("When on, records you add from a scan or search are added to your Discogs collection (skipping any already there). Manual entries and edits aren’t synced.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func sourceRow(index: Int, name: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(index)").font(.prBadge).foregroundStyle(Palette.quaternary)
                Text(name).font(.prBody).foregroundStyle(Palette.label)
                Spacer()
            }
            .padding(.vertical, 12)
            if divider { HRule() }
        }
    }

    // MARK: Cover art

    private var currentCoverSource: CoverSource {
        CoverSource(rawValue: coverSourceRaw) ?? .appleMusic
    }

    private var coverArtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Cover art")
            GroupedCard(radius: 14) {
                VStack(spacing: 0) {
                    Menu {
                        ForEach(CoverSource.allCases) { source in
                            Button {
                                coverSourceRaw = source.rawValue
                            } label: {
                                if source.rawValue == coverSourceRaw {
                                    Label(source.displayName, systemImage: "checkmark")
                                } else {
                                    Text(source.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Preferred source").font(.prBody).foregroundStyle(Palette.label)
                            Spacer()
                            Text(currentCoverSource.displayName).font(.prBody).foregroundStyle(Palette.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                        }
                        .padding(.vertical, 12)
                    }
                    HRule()
                    HStack {
                        Text("Choose cover when adding").font(.prBody).foregroundStyle(Palette.label)
                        Spacer()
                        Toggle("", isOn: $pickCoverOnImport).labelsHidden().tint(Palette.accent)
                    }
                    .padding(.vertical, 6)
                }
            }
            Text("Apple Music has the cleanest artwork; Cover Art Archive and Discogs cover more pressings. With “Choose cover when adding” off, the preferred source is used automatically.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Collection

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Collection")
            GroupedCard(radius: 14) {
                NavigationLink {
                    LocationsView()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.accent.opacity(0.16))
                                .frame(width: 30, height: 30)
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                        }
                        Text("Locations").font(.prBody).foregroundStyle(Palette.label)
                        Spacer()
                        Text(locationSummary).font(.prBody).foregroundStyle(Palette.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.quaternary)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            Text("Track where records live — a shelf, a room, another country. The default is preselected when adding a record.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private var locationSummary: String {
        switch library.locations.count {
        case 0: return "None"
        case 1: return "1 place"
        case let count: return "\(count) places"
        }
    }

    // MARK: Storage

    private var iCloudToggle: Binding<Bool> {
        Binding(
            get: { app.prefersICloud && app.iCloudAvailable },
            set: { app.setPreferICloud($0) }
        )
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Storage")
            GroupedCard(radius: 14, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(app.storageMode == .iCloud ? Palette.iCloudBlue : Color(hex: 0x48484A))
                                .frame(width: 38, height: 38)
                            Image(systemName: app.storageMode == .iCloud ? "icloud.fill" : "internaldrive.fill")
                                .foregroundStyle(.white).font(.system(size: 18))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.storageMode == .iCloud ? "iCloud Drive" : "On this iPhone")
                                .font(.prBodyEmphasis).foregroundStyle(Palette.label)
                            Text(app.storageMode == .iCloud ? "Pacific Record · visible in Files"
                                                            : "Documents / Pacific Record")
                                .font(.prSmall).foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                        if app.switchingStorage { ProgressView().controlSize(.small) }
                    }
                    .padding(.bottom, 12)
                    HRule()
                    if AppConfig.iCloudEnabled {
                        HStack {
                            Text("Use iCloud Drive").font(.prBody).foregroundStyle(Palette.label)
                            Spacer()
                            Toggle("", isOn: iCloudToggle)
                                .labelsHidden()
                                .tint(Palette.accent)
                                .disabled(!app.iCloudAvailable || app.switchingStorage)
                        }
                        .padding(.top, 10)
                        if !app.iCloudAvailable {
                            Text("Sign in to iCloud and turn on iCloud Drive to sync across devices.")
                                .font(.prSmall).foregroundStyle(Palette.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    } else {
                        Text("iCloud sync is off in this build — enable it once the app is signed with a paid Apple Developer account.")
                            .font(.prSmall).foregroundStyle(Palette.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                }
            }

            Text("Your library is a plain SQLite file plus a Covers folder — other apps can open it directly.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)
        }
    }
}
