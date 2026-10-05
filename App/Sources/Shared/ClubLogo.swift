import SwiftUI

/// Club crest from its public storage URL; initials in a circle while loading or when missing.
struct ClubLogo: View {
    let url: String?
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed, transaction: Transaction(animation: .easeIn(duration: 0.15))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    /// "Blau Weiss Gottschee" → "BW"; "IFA" → "IF".
    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        if words.count >= 2 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}
