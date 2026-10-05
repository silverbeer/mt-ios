import Foundation

/// Monday–Sunday week used by the Matches tab, matching the Android app
/// (domain/MatchWeek.kt) and the web (MatchesView getWeekBoundaries).
public struct MatchWeek: Sendable, Equatable {
    public let start: Date
    public let end: Date

    /// Week containing `today`, shifted by `offset` weeks (-1 = last week, +1 = next).
    public init(containing today: Date, offset: Int = 0, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: today)
        // weekday: Sunday = 1 … Saturday = 7, so Sunday steps back 6 days, not 0.
        let daysFromMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday + offset * 7, to: day) ?? day
        start = monday
        end = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
    }

    /// `YYYY-MM-DD` bounds for `start_date` / `end_date`.
    public var startDay: String { MTDate.dayString(start) }
    public var endDay: String { MTDate.dayString(end) }

    /// Whether a `YYYY-MM-DD` match date falls in this week.
    public func contains(day: String) -> Bool { day >= startDay && day <= endDay }

    /// "Oct 5 – Oct 11, 2026", the Android label format.
    public var label: String {
        let short = Date.FormatStyle().month(.abbreviated).day()
        let long = Date.FormatStyle().month(.abbreviated).day().year()
        return "\(start.formatted(short)) – \(end.formatted(long))"
    }
}
