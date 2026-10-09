import SwiftUI
import MTKit

/// A club or team shown as its initials in a circle. The app never shows club
/// crests (a product decision), so this has no image or network path.
/// Hidden from VoiceOver: every use sits beside the full name.
struct ClubBadge: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(ClubInitials.from(name))
                    .font(.system(size: size * (size < 24 ? 0.38 : 0.4), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(size * 0.08)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
