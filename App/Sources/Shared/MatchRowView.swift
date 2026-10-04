import SwiftUI
import MTKit

struct MatchRowView: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(match.homeTeamName).lineLimit(1)
                Text(match.awayTeamName).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if match.hasScore {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(match.homeScore ?? 0)")
                    Text("\(match.awayScore ?? 0)")
                }
                .font(.body.monospacedDigit().bold())
            }
            MatchStatusBadge(match: match).frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
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
