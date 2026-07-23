import SwiftUI
import VinylCore

/// Manage the list of physical locations: add, rename, delete, set the default.
struct LocationsView: View {
    @Environment(LibraryModel.self) private var model

    @State private var showAdd = false
    @State private var newName = ""
    @State private var renameTarget: Location?
    @State private var renameName = ""
    @State private var deleteTarget: Location?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.locations.isEmpty {
                    emptyState
                } else {
                    GroupedCard(radius: 14) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.locations.enumerated()), id: \.element.id) { index, location in
                                row(location)
                                if index < model.locations.count - 1 { HRule() }
                            }
                        }
                    }
                    Text("Use the ••• menu to rename, delete, or set the default. The default is preselected when adding a record.")
                        .font(.prSmall).foregroundStyle(Palette.tertiary).padding(.horizontal, 4)
                }

                Button { newName = ""; showAdd = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20))
                        Text("Add location").font(.prBodyEmphasis)
                        Spacer()
                    }
                    .foregroundStyle(Palette.tint)
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .background(Palette.grouped, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
        }
        .background(Palette.background)
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New location", isPresented: $showAdd) {
            TextField("Name", text: $newName)
            Button("Add") { _ = model.addLocation(newName); newName = "" }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("A shelf, a room, a house — anywhere records live.")
        }
        .alert("Rename location", isPresented: renameActive) {
            TextField("Name", text: $renameName)
            Button("Save") {
                if let target = renameTarget { model.renameLocation(target.id, to: renameName) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteActive, titleVisibility: .visible) {
            Button("Delete location", role: .destructive) {
                if let target = deleteTarget { model.deleteLocation(target.id) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Records stored here become unassigned.")
        }
    }

    private func row(_ location: Location) -> some View {
        HStack(spacing: 10) {
            Text(location.name).font(.prBody).foregroundStyle(Palette.label)
            if location.isDefault {
                Text("Default")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.accent.opacity(0.15), in: Capsule())
            }
            Spacer()
            Menu {
                if !location.isDefault {
                    Button { model.setDefaultLocation(location.id) } label: {
                        Label("Set as default", systemImage: "star")
                    }
                }
                Button { renameTarget = location; renameName = location.name } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) { deleteTarget = location } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("\(location.name) options")
        }
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 34)).foregroundStyle(Palette.tertiary)
            Text("No locations yet").font(.prBodyEmphasis).foregroundStyle(Palette.label)
            Text("Add places like “Living-room shelf” or “Storage — Berlin”.")
                .font(.prSmall).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var renameActive: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteActive: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteTitle: String {
        deleteTarget.map { "Delete “\($0.name)”?" } ?? "Delete location?"
    }
}
