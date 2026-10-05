import Foundation

extension MatchEvent {
    public enum Kind: Sendable, Equatable {
        case goal, yellowCard, redCard, substitution, statusChange, message, other(String)
    }

    public var kind: Kind {
        switch eventType {
        case "goal": .goal
        case "yellow_card": .yellowCard
        case "red_card": .redCard
        case "substitution": .substitution
        case "status_change": .statusChange
        case "message": .message
        default: .other(eventType)
        }
    }

    /// "23'" or "90+5'"; empty when the event has no minute.
    public var minuteLabel: String {
        guard let minute = matchMinute else { return "" }
        if let extra = extraTime, extra > 0 { return "\(minute)+\(extra)'" }
        return "\(minute)'"
    }

    /// Sort key: match minute (stoppage time after the minute), then creation order.
    var order: (Int, Int, String, Int) { (matchMinute ?? .max, extraTime ?? 0, createdAt ?? "", id) }
}

/// A match's events arranged for the match view, as the web MatchDetailView does:
/// goals and cards per team in minute order, plus the full timeline.
public struct MatchTimeline: Sendable, Equatable {
    public var homeGoals: [MatchEvent]
    public var awayGoals: [MatchEvent]
    public var homeCards: [MatchEvent]
    public var awayCards: [MatchEvent]
    /// Everything, oldest first (by creation time, which is how it happened).
    public var all: [MatchEvent]

    public init(events: [MatchEvent], homeTeamId: Int, awayTeamId: Int) {
        let byMinute = events.sorted { $0.order < $1.order }
        func pick(_ kinds: [MatchEvent.Kind], _ team: Int) -> [MatchEvent] {
            byMinute.filter { kinds.contains($0.kind) && $0.teamId == team }
        }
        homeGoals = pick([.goal], homeTeamId)
        awayGoals = pick([.goal], awayTeamId)
        homeCards = pick([.yellowCard, .redCard], homeTeamId)
        awayCards = pick([.yellowCard, .redCard], awayTeamId)
        all = events.sorted { (($0.createdAt ?? ""), $0.id) < (($1.createdAt ?? ""), $1.id) }
    }

    public var isEmpty: Bool { all.isEmpty }
}

/// Live match clock derived from the match's phase timestamps. Same rules as the
/// Android LiveClock and the backend's calculate_match_minute: the second half
/// continues from `halfDuration`, half-time shows "HT", a finished match "FT".
public enum LiveClock {
    public struct Reading: Sendable, Equatable {
        public var display: String
        public var minute: Int?
        public var extraTime: Int?
    }

    public static func read(_ state: LiveMatchState, now: Date = Date()) -> Reading {
        let half = state.halfDuration ?? 45
        guard let kickoff = state.kickoffTime.flatMap(MTDate.timestamp) else {
            return Reading(display: "—", minute: nil, extraTime: nil)
        }
        if state.matchEndTime != nil { return Reading(display: "FT", minute: nil, extraTime: nil) }
        if let secondHalf = state.secondHalfStart.flatMap(MTDate.timestamp) {
            let seconds = Int(now.timeIntervalSince(secondHalf)) + half * 60
            return reading(seconds: seconds, cap: half * 2)
        }
        if state.halftimeStart != nil { return Reading(display: "HT", minute: half, extraTime: nil) }
        return reading(seconds: Int(now.timeIntervalSince(kickoff)), cap: half)
    }

    private static func reading(seconds: Int, cap: Int) -> Reading {
        let s = max(seconds, 0)
        let minute = s / 60
        return Reading(display: String(format: "%02d:%02d", s / 60, s % 60),
                       minute: min(minute, cap), extraTime: minute > cap ? minute - cap : nil)
    }
}

extension APIClient {
    /// Up to 100 events for a match (goals, cards, subs, status changes).
    public func events(matchId: Int) async throws -> [MatchEvent] {
        try await get("/api/matches/\(matchId)/live/events", query: ["limit": "100"])
    }
}
