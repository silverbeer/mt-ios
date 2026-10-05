import Foundation

// Wire models for the Missing Table backend. Field names follow the backend's
// snake_case JSON via `JSONDecoder.mt` (convertFromSnakeCase). Optional fields
// mirror what the backend may omit or null; the Android client's Dtos.kt is the
// reference for which fields are guaranteed.

public struct User: Codable, Sendable, Equatable {
    public var id: String
    public var username: String?
    public var email: String?
    public var displayName: String?
    public var role: String?
    public var teamId: Int?
    public var clubId: Int?

    public init(id: String, username: String? = nil, email: String? = nil, displayName: String? = nil,
                role: String? = nil, teamId: Int? = nil, clubId: Int? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.role = role
        self.teamId = teamId
        self.clubId = clubId
    }

    /// Name to show in the UI.
    public var label: String { displayName ?? username ?? email ?? "Signed in" }
}

public struct Season: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var isCurrent: Bool?
    public var startDate: String?

    public init(id: Int, name: String, isCurrent: Bool? = nil, startDate: String? = nil) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
        self.startDate = startDate
    }
}

public struct AgeGroup: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct League: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var isActive: Bool?
    public var displayOrder: Int?

    public init(id: Int, name: String, isActive: Bool? = nil, displayOrder: Int? = nil) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.displayOrder = displayOrder
    }
}

public struct Division: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var leagueId: Int?

    public init(id: Int, name: String, leagueId: Int? = nil) {
        self.id = id
        self.name = name
        self.leagueId = leagueId
    }
}

public struct StandingRow: Codable, Sendable, Equatable, Identifiable {
    public var team: String
    public var teamId: Int?
    public var clubId: Int?
    public var logoUrl: String?
    public var played: Int
    public var wins: Int
    public var draws: Int
    public var losses: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var goalDifference: Int
    public var points: Int
    public var form: [String]?
    public var positionChange: Int?

    public var id: String { teamId.map(String.init) ?? team }

    public init(team: String, teamId: Int? = nil, clubId: Int? = nil, logoUrl: String? = nil,
                played: Int = 0, wins: Int = 0, draws: Int = 0, losses: Int = 0,
                goalsFor: Int = 0, goalsAgainst: Int = 0, goalDifference: Int = 0, points: Int = 0,
                form: [String]? = nil, positionChange: Int? = nil) {
        self.team = team
        self.teamId = teamId
        self.clubId = clubId
        self.logoUrl = logoUrl
        self.played = played
        self.wins = wins
        self.draws = draws
        self.losses = losses
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.goalDifference = goalDifference
        self.points = points
        self.form = form
        self.positionChange = positionChange
    }
}

extension StandingRow {
    // Counts default to 0 when absent, matching the Android client's StandingRow.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        self.init(team: try c.decodeIfPresent(String.self, forKey: .team) ?? "",
                  teamId: try c.decodeIfPresent(Int.self, forKey: .teamId),
                  clubId: try c.decodeIfPresent(Int.self, forKey: .clubId),
                  logoUrl: try c.decodeIfPresent(String.self, forKey: .logoUrl),
                  played: try count(.played), wins: try count(.wins), draws: try count(.draws),
                  losses: try count(.losses), goalsFor: try count(.goalsFor),
                  goalsAgainst: try count(.goalsAgainst), goalDifference: try count(.goalDifference),
                  points: try count(.points),
                  form: try c.decodeIfPresent([String].self, forKey: .form),
                  positionChange: try c.decodeIfPresent(Int.self, forKey: .positionChange))
    }
}

struct TableResponse: Decodable, Sendable {
    var standings: [StandingRow]
}

public struct TeamClub: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
    public var logoUrl: String?
    public var primaryColor: String?
    public var secondaryColor: String?
}

public enum MatchStatus: Sendable, Equatable, Hashable, Codable {
    case scheduled, tbd, live, completed, postponed, cancelled, forfeit
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "scheduled": self = .scheduled
        case "tbd": self = .tbd
        case "live": self = .live
        case "completed": self = .completed
        case "postponed": self = .postponed
        case "cancelled": self = .cancelled
        case "forfeit": self = .forfeit
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .scheduled: "scheduled"
        case .tbd: "tbd"
        case .live: "live"
        case .completed: "completed"
        case .postponed: "postponed"
        case .cancelled: "cancelled"
        case .forfeit: "forfeit"
        case .unknown(let value): value
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Result is final and will not change.
    public var isFinal: Bool { self == .completed || self == .forfeit }
}

public struct Match: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var matchDate: String
    public var scheduledKickoff: String?
    public var homeTeamId: Int
    public var awayTeamId: Int
    public var homeTeamName: String
    public var awayTeamName: String
    public var homeScore: Int?
    public var awayScore: Int?
    public var homePenaltyScore: Int?
    public var awayPenaltyScore: Int?
    public var matchStatus: MatchStatus?
    public var seasonId: Int?
    public var ageGroupId: Int?
    public var ageGroupName: String?
    public var divisionId: Int?
    public var divisionName: String?
    public var leagueName: String?
    public var matchTypeName: String?
    public var seasonName: String?
    public var scoringMode: String?
    public var homeTeamClub: TeamClub?
    public var awayTeamClub: TeamClub?

    public init(id: Int, matchDate: String, scheduledKickoff: String? = nil,
                homeTeamId: Int, awayTeamId: Int, homeTeamName: String, awayTeamName: String,
                homeScore: Int? = nil, awayScore: Int? = nil,
                homePenaltyScore: Int? = nil, awayPenaltyScore: Int? = nil,
                matchStatus: MatchStatus? = nil, seasonId: Int? = nil,
                ageGroupId: Int? = nil, ageGroupName: String? = nil,
                divisionId: Int? = nil, divisionName: String? = nil, leagueName: String? = nil,
                matchTypeName: String? = nil, homeTeamClub: TeamClub? = nil, awayTeamClub: TeamClub? = nil) {
        self.id = id
        self.matchDate = matchDate
        self.scheduledKickoff = scheduledKickoff
        self.homeTeamId = homeTeamId
        self.awayTeamId = awayTeamId
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homePenaltyScore = homePenaltyScore
        self.awayPenaltyScore = awayPenaltyScore
        self.matchStatus = matchStatus
        self.seasonId = seasonId
        self.ageGroupId = ageGroupId
        self.ageGroupName = ageGroupName
        self.divisionId = divisionId
        self.divisionName = divisionName
        self.leagueName = leagueName
        self.matchTypeName = matchTypeName
        self.homeTeamClub = homeTeamClub
        self.awayTeamClub = awayTeamClub
    }

    public var status: MatchStatus { matchStatus ?? .scheduled }
    /// Scored live from the touchline app, so it has an event timeline.
    public var isLiveScored: Bool { scoringMode == "live" }
    public var hasScore: Bool { homeScore != nil && awayScore != nil }
}

/// Minimal row from `GET /api/matches/live`.
public struct LiveMatchSummary: Codable, Sendable, Equatable, Identifiable {
    public var matchId: Int
    public var matchStatus: MatchStatus?
    public var homeScore: Int?
    public var awayScore: Int?
    public var homeTeamName: String?
    public var awayTeamName: String?
    public var kickoffTime: String?

    public var id: Int { matchId }

    public init(matchId: Int, matchStatus: MatchStatus? = nil, homeScore: Int? = nil, awayScore: Int? = nil,
                homeTeamName: String? = nil, awayTeamName: String? = nil, kickoffTime: String? = nil) {
        self.matchId = matchId
        self.matchStatus = matchStatus
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.kickoffTime = kickoffTime
    }
}

public struct MatchEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var matchId: Int
    public var eventType: String
    public var teamId: Int?
    public var playerName: String?
    public var assistPlayerName: String?
    public var matchMinute: Int?
    public var extraTime: Int?
    public var message: String?
    public var createdAt: String?
    public var createdBy: String?
    public var createdByUsername: String?
}

/// `GET /api/matches/{id}/live` — the live clock fields the minute is derived from.
public struct LiveMatchState: Codable, Sendable, Equatable {
    public var matchId: Int?
    public var matchStatus: MatchStatus?
    public var homeScore: Int?
    public var awayScore: Int?
    public var kickoffTime: String?
    public var halftimeStart: String?
    public var secondHalfStart: String?
    public var matchEndTime: String?
    public var halfDuration: Int?
    public var homeTeamId: Int?
    public var homeTeamName: String?
    public var awayTeamId: Int?
    public var awayTeamName: String?
    public var recentEvents: [MatchEvent]?
}
