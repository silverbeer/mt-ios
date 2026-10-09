import SwiftUI
import MTKit

struct MatchRowView: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ClubBadge(name: match.homeTeamName, size: 20)
                    Text(match.homeTeamName).lineLimit(1)
                }
                HStack(spacing: 8) {
                    ClubBadge(name: match.awayTeamName, size: 20)
                    Text(match.awayTeamName).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if match.hasScore {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(match.homeScore ?? 0)")
                    Text("\(match.awayScore ?? 0)")
                }
                .font(.body.monospacedDigit().bold())
            }
            VStack(alignment: .trailing, spacing: 6) {
                MatchStatusBadge(match: match)
                if let competition = match.competition { CompetitionChip(competition: competition) }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// LEAGUE / FLEX pill, tinted like the web (navy for League, amber for Flex).
struct CompetitionChip: View {
    let competition: Competition

    var body: some View {
        let (background, foreground) = tint
        Text(competition.label)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(foreground)
            .accessibilityLabel(competition.label.capitalized)
    }

    /// Web tailwind tints (brand / accent / purple 100 + 700), swapped in dark mode.
    private var tint: (Color, Color) {
        switch competition {
        case .league: Self.pair(light: 0xD4E0F5, dark: 0x152C75)
        case .flex: Self.pair(light: 0xFDE8BF, dark: 0x8F3F0A)
        case .tournament: Self.pair(light: 0xF3E8FF, dark: 0x6B21A8)
        case .friendly, .other: (Color(.secondarySystemFill), .secondary)
        }
    }

    private static func pair(light: UInt32, dark: UInt32) -> (Color, Color) {
        (adaptive(light, dark), adaptive(dark, light))
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ rgb: UInt32) -> UIColor {
            UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

struct MatchStatusBadge: View {
    let match: Match

    var body: some View {
        switch match.status {
        case .live:
            Text("LIVE")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red, in: Capsule())
                .foregroundStyle(.white)
        case .completed:
            Text("FT").font(.caption.bold()).foregroundStyle(.secondary)
        case .forfeit:
            Text("Forfeit").font(.caption).foregroundStyle(.secondary)
        case .postponed:
            Text("Postponed").font(.caption).foregroundStyle(.orange)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        case .scheduled, .tbd, .unknown:
            Text(match.kickoffLabel).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Match {
    /// Local kickoff time, or "TBD".
    var kickoffLabel: String {
        guard let kickoff = scheduledKickoff.flatMap(MTDate.timestamp) else { return "TBD" }
        return kickoff.formatted(date: .omitted, time: .shortened)
    }
}

/// Section title for a `YYYY-MM-DD` day: "Today", "Sat, Oct 4".
func dayTitle(_ day: String) -> String {
    guard let date = MTDate.date(fromDay: day) else { return day }
    if Calendar.current.isDateInToday(date) { return "Today" }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
    return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}
