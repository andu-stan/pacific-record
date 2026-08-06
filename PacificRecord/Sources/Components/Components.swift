import SwiftUI
import VinylCore

// MARK: - Condition badge

/// Text + fill colors for a Goldmine grade: green for M/NM, amber for VG+/VG,
/// neutral for anything lower.
func conditionPalette(_ condition: Condition) -> (text: Color, fill: Color) {
    switch condition {
    case .mint, .nearMint:
        return (Palette.badgeGreenText, Palette.badgeGreenFill)
    case .veryGoodPlus, .veryGood:
        return (Palette.badgeAmberText, Palette.badgeAmberFill)
    case .goodPlus, .good, .fair, .poor:
        return (Palette.secondary, Palette.badgeNeutralFill)
    }
}

/// Solid fill for a *selected* grade chip, paired with white text. The tinted
/// palette above is too close to the unselected style for the lower grades.
func conditionSolidColor(_ condition: Condition) -> Color {
    switch condition {
    case .mint, .nearMint:          return Palette.gradeGreenSolid
    case .veryGoodPlus, .veryGood:  return Palette.gradeAmberSolid
    case .goodPlus, .good:          return Palette.gradeSlateSolid
    case .fair, .poor:              return Palette.gradeRedSolid
    }
}

struct ConditionBadge: View {
    let condition: Condition
    var fontSize: CGFloat = 13

    var body: some View {
        let palette = conditionPalette(condition)
        Text(condition.rawValue)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: Metrics.badgeRadius, style: .continuous))
    }
}

/// A neutral "media grade" pill used in the list rows (grade text only).
struct GradePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.badgeNeutralFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Star rating

struct StarRatingView: View {
    let rating: Int          // 0...5
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(index < rating ? Palette.accent : Palette.starEmpty)
            }
        }
        .accessibilityLabel("\(rating) out of 5")
    }
}

/// Interactive rating used in the edit form.
struct StarRatingPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(value <= rating ? Palette.accent : Palette.starEmpty)
                    .onTapGesture { rating = (rating == value) ? value - 1 : value }
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.prHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
                .shadow(color: Palette.accent.opacity(0.35), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.prHeadline)
                .foregroundStyle(Palette.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grouped card & rows

struct GroupedCard<Content: View>: View {
    var radius: CGFloat = Metrics.cardRadius
    var padding: EdgeInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Palette.grouped, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
    }
}

/// A hairline separator in the design's separator color.
struct HRule: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1)
    }
}

/// Label on the left, value on the right — the info-card row.
struct InfoRow: View {
    let label: String
    let value: String
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.prBody).foregroundStyle(Palette.secondary)
                Spacer(minLength: 12)
                Text(value).font(.prBodyEmphasis).foregroundStyle(Palette.label)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 11)
            if showsDivider { HRule() }
        }
    }
}

/// Uppercase, tracked section header (e.g. "METADATA", "GENRE & STYLES").
struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.prCaption)
            .tracking(0.6)
            .foregroundStyle(Palette.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Full-screen states

/// Loading spinner + message (metadata lookup).
struct LoadingStateView: View {
    var title: String = "Looking up release…"
    var message: String

    var body: some View {
        VStack(spacing: 0) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.accent)
                .padding(.bottom, 24)
            Text(title).font(.prSection).foregroundStyle(Palette.label)
                .padding(.bottom, 8)
            Text(message)
                .font(.prBody)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

/// A centered icon + title + message + up to two actions.
struct MessageStateView: View {
    let systemImage: String
    var iconColor: Color = Palette.secondary
    var iconBackground: Color = Palette.grouped
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(iconBackground).frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(iconColor)
            }
            .padding(.bottom, 24)

            Text(title).font(.prTitle2).foregroundStyle(Palette.label).padding(.bottom, 8)
            Text(message)
                .font(.prBody).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            if let primaryTitle, let primaryAction {
                PrimaryButton(title: primaryTitle, action: primaryAction).padding(.bottom, 12)
            }
            if let secondaryTitle, let secondaryAction {
                SecondaryButton(title: secondaryTitle, action: secondaryAction)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
