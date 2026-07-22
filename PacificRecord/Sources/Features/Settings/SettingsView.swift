import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("discogsToken") private var token = ""
    @State private var showTokenEntry = false
    @State private var tokenDraft = ""

    private var isConnected: Bool { !token.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                metadataSection
                storageSection
                HStack(spacing: 12) {
                    PrimaryButton(title: "Back up now") {}
                    Button {} label: {
                        Text("Backups")
                            .font(.prBodyEmphasis)
                            .foregroundStyle(Palette.tint)
                            .padding(.vertical, 15).padding(.horizontal, 18)
                            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
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

            Text("Source order — dragged to reorder lookups.")
                .font(.prSmall).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 4)

            GroupedCard(radius: 14) {
                VStack(spacing: 0) {
                    sourceRow(index: 1, name: "Discogs", divider: true)
                    sourceRow(index: 2, name: "MusicBrainz", divider: false)
                }
            }
        }
    }

    private func sourceRow(index: Int, name: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(index)").font(.prBadge).foregroundStyle(Palette.quaternary)
                Text(name).font(.prBody).foregroundStyle(Palette.label)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(.vertical, 12)
            if divider { HRule() }
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "Storage")
            GroupedCard(radius: 14, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Palette.iCloudBlue).frame(width: 38, height: 38)
                            Image(systemName: "icloud.fill").foregroundStyle(.white).font(.system(size: 18))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Drive").font(.prBodyEmphasis).foregroundStyle(Palette.label)
                            Text("Pacific Record / Library.prlib")
                                .font(.prSmall).foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 12)
                    HRule()
                    storageRow("Last synced", "Today, 9:32 AM")
                    storageRow("Library size", "248 records · 84 MB")
                    HRule()
                    Button {} label: {
                        Text("Reveal in Files")
                            .font(.prFootnote).foregroundStyle(Palette.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func storageRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.prFootnote).foregroundStyle(Palette.secondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.label)
        }
        .padding(.vertical, 8)
    }
}
