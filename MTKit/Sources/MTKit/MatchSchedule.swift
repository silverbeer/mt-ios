import Foundation

/// Splits a match list into what a schedule screen shows: live now, results
/// (newest first) and fixtures (soonest first), with results and fixtures
/// grouped by `match_date`.
public struct MatchSchedule: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var date: String
        public var matches: [Match]
        public var id: String { date }
    }

    public var live: [Match]
    public var results: [Day]
    public var fixtures: [Day]

    public init(_ matches: [Match]) {
        live = matches.filter { $0.status == .live }.sorted(by: Self.kickoffAscending)
        let rest = matches.filter { $0.status != .live }
        let played = rest.filter { $0.status.isFinal || ($0.hasScore && $0.status != .scheduled) }
        let playedIds = Set(played.map(\.id))
        let upcoming = rest.filter { !playedIds.contains($0.id) }
        results = Self.days(played, newestFirst: true)
        fixtures = Self.days(upcoming, newestFirst: false)
    }

    public var isEmpty: Bool { live.isEmpty && results.isEmpty && fixtures.isEmpty }

    /// Keep only matches involving any of `teamIds`.
    public static func involving(_ teamIds: Set<Int>, in matches: [Match]) -> [Match] {
        matches.filter { teamIds.contains($0.homeTeamId) || teamIds.contains($0.awayTeamId) }
    }

    private static func days(_ matches: [Match], newestFirst: Bool) -> [Day] {
        Dictionary(grouping: matches, by: \.matchDate)
            .map { Day(date: $0.key, matches: $0.value.sorted(by: kickoffAscending)) }
            .sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    private static func kickoffAscending(_ a: Match, _ b: Match) -> Bool {
        (a.scheduledKickoff ?? a.matchDate, a.id) < (b.scheduledKickoff ?? b.matchDate, b.id)
    }
}

public enum MTDate {
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Parses `YYYY-MM-DD` (as local calendar date).
    public static func date(fromDay string: String) -> Date? { day.date(from: string) }

    /// Formats as `YYYY-MM-DD` in the current calendar.
    public static func dayString(_ date: Date) -> String { day.string(from: date) }

    /// Parses backend timestamps, with or without fractional seconds.
    public static func timestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
