import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x2A1C10), Palette.background],
                center: .top, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                logo
                    .padding(.bottom, 28)

                Text("Your collection,\ntruly yours.")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .padding(.bottom, 16)

                (Text("Pacific Record keeps your library as an open file in ")
                    + Text("iCloud Drive").foregroundColor(Palette.label).fontWeight(.semibold)
                    + Text(" — so it's backed up, synced across devices, and readable by other apps. No lock-in, ever."))
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.secondary)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 16) {
                    bullet("Scan a barcode to auto-fill releases")
                    bullet("Track Goldmine condition & pressings")
                    bullet("Optional Discogs token for richer data")
                }

                Spacer(minLength: 24)

                PrimaryButton(title: "Continue", action: onContinue)
                    .padding(.bottom, 12)
                Button(action: onContinue) {
                    Text("Add Discogs token later")
                        .font(.prHeadline)
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
        }
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xE8833A), Color(hex: 0xC1440E)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 78, height: 78)
                .shadow(color: Palette.accent.opacity(0.4), radius: 20, y: 12)
            Circle().fill(.black).frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                .overlay(Circle().fill(.black).frame(width: 8, height: 8))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.2)).frame(width: 26, height: 26)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.badgeAmberText)
            }
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(Palette.label.opacity(0.85))
        }
    }
}
