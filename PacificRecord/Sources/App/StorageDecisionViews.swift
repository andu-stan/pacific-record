import SwiftUI
import VinylCore

/// The iCloud library exists but hasn't arrived on this device yet.
///
/// The app deliberately refuses to open the path in this state: the file isn't
/// there under its own name, so SQLite would create an empty one, and iCloud
/// would then have two versions of the same library to reconcile.
struct ICloudDownloadingView: View {
    var onRetry: () -> Void
    var onUseLocal: () -> Void

    var body: some View {
        MessageStateView(
            systemImage: "icloud.and.arrow.down",
            iconColor: Palette.iCloudBlue,
            title: "Getting your library",
            message: "Your library is still downloading from iCloud. That's usually quick, but a first sync on a new iPhone can take a while on a slow connection.",
            primaryTitle: "Check again",
            primaryAction: onRetry,
            secondaryTitle: "Use this iPhone's copy for now",
            secondaryAction: onUseLocal
        )
    }
}

/// Both this iPhone and iCloud hold a library, and neither has been superseded.
///
/// There is no safe automatic answer here — picking either side silently is how
/// a collection gets overwritten — so the app asks. Every option leaves both
/// files on disk; the one that doesn't win is renamed aside, never deleted.
struct LibraryChoiceView: View {
    let conflict: StorageConflict
    var onChoose: (AppModel.LibraryChoice) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(Palette.grouped).frame(width: 88, height: 88)
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(Palette.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 24)

                Text("Two libraries found")
                    .font(.prTitle2)
                    .foregroundStyle(Palette.label)
                    .padding(.bottom, 8)
                Text("This iPhone and your iCloud Drive each hold a Pacific Record library. Choose which one to carry on with — whichever you don't pick is kept on this iPhone under a dated name, not deleted.")
                    .font(.prBody)
                    .foregroundStyle(Palette.secondary)
                    .padding(.bottom, 24)

                VStack(spacing: 12) {
                    option(
                        icon: "icloud",
                        title: "Keep the iCloud library",
                        subtitle: "\(count(conflict.cloudRecordCount)) · syncs with your other devices"
                    ) { onChoose(.keepICloud) }

                    option(
                        icon: "iphone",
                        title: "Keep this iPhone's library",
                        subtitle: "\(count(conflict.localRecordCount)) · replaces what's in iCloud"
                    ) { onChoose(.keepThisDevice) }

                    option(
                        icon: "arrow.triangle.merge",
                        title: "Merge them",
                        subtitle: "Adds this iPhone's records to the iCloud library, keeping both"
                    ) { onChoose(.merge) }
                }

                Text("Merging only ever adds. A record that's in both keeps its iCloud version, so nothing you have is overwritten.")
                    .font(.prSmall)
                    .foregroundStyle(Palette.tertiary)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .background(Palette.background)
    }

    private func count(_ value: Int) -> String {
        value == 1 ? "1 record" : "\(value.formatted()) records"
    }

    private func option(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Palette.accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.prHeadline).foregroundStyle(Palette.label)
                    Text(subtitle)
                        .font(.prFootnote)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.quaternary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
