import SwiftUI

extension Color {
    /// `#RRGGBB` / `RRGGBB` from the backend's club and profile colours.
    init?(hex: String?) {
        guard var value = hex?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

/// Round player photo with an initial when there's no photo.
struct PlayerAvatar: View {
    let url: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle().fill(.quaternary).overlay {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Grid of labelled numbers (stats tiles).
struct StatGrid: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var highlight = false
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    Text(item.value)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(item.highlight ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Text(item.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
