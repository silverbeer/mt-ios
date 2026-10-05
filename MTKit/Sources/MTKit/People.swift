import Foundation

// Profiles, rosters and player stats (backend app.py /api/auth/me, /api/me/player-stats,
// /api/teams/{id}/roster, /api/roster/{id}/stats, /api/teams/{id}/stats,
// /api/leaderboards/goals). Shapes follow the web profile components.

public struct NamedRef: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?

    public init(id: Int? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

public struct ClubRef: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
    public var logoUrl: String?
    public var primaryColor: String?
    public var secondaryColor: String?
}

public struct TeamRef: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
    public var city: String?
    public var club: ClubRef?
    public var league: NamedRef?
    public var division: NamedRef?
}

/// One of the user's current team assignments (`current_teams` on /api/auth/me).
public struct CurrentTeam: Codable, Sendable, Equatable, Hashable {
    public var teamId: Int?
    public var team: TeamRef?
    public var season: NamedRef?
    public var ageGroup: NamedRef?
    public var league: NamedRef?
    public var division: NamedRef?

    public var name: String { team?.name ?? "Team" }
    /// "U15 · Homegrown · Northeast".
    public var subtitle: String {
        [ageGroup?.name, league?.name ?? team?.league?.name, division?.name ?? team?.division?.name]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Account roles. Hyphen and underscore spellings both occur in the data (backend auth.py).
public enum Role: String, Sendable, Equatable, CaseIterable {
    case admin
    case clubManager = "club-manager"
    case teamManager = "team-manager"
    case player = "team-player"
    case clubFan = "club-fan"
    case teamFan = "team-fan"

    public init(raw: String?) {
        let normalized = (raw ?? "").replacingOccurrences(of: "_", with: "-")
        self = Role(rawValue: normalized) ?? .teamFan
    }

    public var title: String {
        switch self {
        case .admin: "Admin"
        case .clubManager: "Club Manager"
        case .teamManager: "Team Manager"
        case .player: "Player"
        case .clubFan: "Club Fan"
        case .teamFan: "Team Fan"
        }
    }

    public var isManager: Bool { self == .admin || self == .clubManager || self == .teamManager }
    /// Roles that see club team pages (web utils/roles.js TEAM_PAGE_ROLES).
    public var seesClubTeams: Bool { self != .teamFan }
}

/// The signed-in user's full profile from /api/auth/me.
public struct MyProfile: Codable, Sendable, Equatable {
    /// Account id; lives beside `profile` on the wire and is filled in by the client.
    public var id: String?
    public var email: String?
    public var username: String?
    public var role: String?
    public var displayName: String?
    public var name: String?
    public var firstName: String?
    public var lastName: String?
    public var playerNumber: Int?
    public var positions: [String]?
    public var teamId: Int?
    public var clubId: Int?
    public var team: TeamRef?
    public var club: ClubRef?
    public var currentTeams: [CurrentTeam]?
    public var photo1Url: String?
    public var photo2Url: String?
    public var photo3Url: String?
    public var profilePhotoSlot: Int?
    public var overlayStyle: String?
    public var primaryColor: String?
    public var textColor: String?
    public var accentColor: String?
    public var hometown: String?

    public var kind: Role { Role(raw: role) }

    /// Web order: linked display name, first + last, username.
    public var fullName: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return displayName ?? (full.isEmpty ? nil : full) ?? username ?? "Player"
    }

    public var photos: [String] { [photo1Url, photo2Url, photo3Url].compactMap { $0 } }

    /// The chosen avatar slot, falling back to the first photo.
    public var profilePhotoUrl: String? {
        switch profilePhotoSlot {
        case 2: photo2Url ?? photos.first
        case 3: photo3Url ?? photos.first
        default: photo1Url ?? photos.first
        }
    }

    /// Club for display: the profile's club, else the primary team's club.
    public var displayClub: ClubRef? { club ?? team?.club ?? currentTeams?.first?.team?.club }
}

struct ProfileEnvelope: Decodable, Sendable {
    struct Wrapped: Decodable, Sendable {
        var id: String
        var email: String?
        var profile: MyProfile?
    }
    var user: Wrapped

    var profile: MyProfile {
        var profile = user.profile ?? MyProfile(id: user.id)
        profile.id = user.id
        if profile.email == nil { profile.email = user.email }
        return profile
    }
}

extension MyProfile {
    public init(id: String?) {
        self.id = id
    }
}

/// Season totals for one player. Missing counters decode as zero (the backend's
/// no-stats fallback omits assists and cards).
public struct SeasonStats: Codable, Sendable, Equatable {
    public var gamesPlayed: Int
    public var gamesStarted: Int
    public var totalMinutes: Int
    public var totalGoals: Int
    public var totalAssists: Int
    public var totalYellowCards: Int
    public var totalRedCards: Int

    public init(gamesPlayed: Int = 0, gamesStarted: Int = 0, totalMinutes: Int = 0, totalGoals: Int = 0,
                totalAssists: Int = 0, totalYellowCards: Int = 0, totalRedCards: Int = 0) {
        self.gamesPlayed = gamesPlayed
        self.gamesStarted = gamesStarted
        self.totalMinutes = totalMinutes
        self.totalGoals = totalGoals
        self.totalAssists = totalAssists
        self.totalYellowCards = totalYellowCards
        self.totalRedCards = totalRedCards
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        self.init(gamesPlayed: try n(.gamesPlayed), gamesStarted: try n(.gamesStarted),
                  totalMinutes: try n(.totalMinutes), totalGoals: try n(.totalGoals),
                  totalAssists: try n(.totalAssists), totalYellowCards: try n(.totalYellowCards),
                  totalRedCards: try n(.totalRedCards))
    }
}

/// `/api/me/player-stats` and `/api/roster/{id}/stats`.
public struct PlayerStatsResponse: Decodable, Sendable, Equatable {
    public var playerId: Int?
    public var jerseyNumber: Int?
    public var displayName: String?
    public var seasonId: Int?
    public var stats: SeasonStats?
    /// Only on /api/me/player-stats: whether the account is linked to a roster entry.
    public var linked: Bool?
}

/// A roster entry (`players` table) from /api/teams/{id}/roster.
public struct RosterPlayer: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public struct Account: Decodable, Sendable, Equatable, Hashable {
        public var id: String?
        public var displayName: String?
        public var photo1Url: String?
        public var photo2Url: String?
        public var photo3Url: String?
        public var profilePhotoSlot: Int?

        public var photoUrl: String? {
            switch profilePhotoSlot {
            case 2: photo2Url ?? photo1Url
            case 3: photo3Url ?? photo1Url
            default: photo1Url ?? photo2Url ?? photo3Url
            }
        }
    }

    public var id: Int
    public var teamId: Int?
    public var jerseyNumber: Int?
    public var firstName: String?
    public var lastName: String?
    public var positions: [String]?
    public var displayName: String?
    public var hasAccount: Bool?
    public var userProfile: Account?

    public var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? jerseyNumber.map { "#\($0)" } ?? "Player" : full
    }

    public var photoUrl: String? { userProfile?.photoUrl }
}

struct RosterResponse: Decodable, Sendable { var roster: [RosterPlayer] }

/// One row of /api/teams/{id}/stats.
public struct TeamPlayerStats: Decodable, Sendable, Equatable, Identifiable {
    public var playerId: Int
    public var jerseyNumber: Int?
    public var firstName: String?
    public var lastName: String?
    public var gamesPlayed: Int?
    public var gamesStarted: Int?
    public var totalMinutes: Int?
    public var totalGoals: Int?
    public var totalAssists: Int?
    public var totalYellowCards: Int?
    public var totalRedCards: Int?

    public var id: Int { playerId }
    public var name: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? jerseyNumber.map { "#\($0)" } ?? "Player" : full
    }
}

struct TeamStatsResponse: Decodable, Sendable { var players: [TeamPlayerStats] }

/// One row of /api/leaderboards/goals (Golden Boot).
public struct LeaderboardEntry: Decodable, Sendable, Equatable, Identifiable {
    public var playerId: Int
    public var jerseyNumber: Int?
    public var firstName: String?
    public var lastName: String?
    public var teamId: Int?
    public var teamName: String?
    public var goals: Int
    public var gamesPlayed: Int?
    public var rank: Int?
    public var goalsPerGame: Double?

    public var id: Int { playerId }
    public var name: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? jerseyNumber.map { "#\($0)" } ?? "Player" : full
    }
}

/// Win/draw/loss record for a team from its completed matches.
public struct TeamRecord: Sendable, Equatable {
    public var played = 0, wins = 0, draws = 0, losses = 0, goalsFor = 0, goalsAgainst = 0

    public init(teamId: Int, matches: [Match]) {
        for match in matches where match.status.isFinal {
            guard let home = match.homeScore, let away = match.awayScore else { continue }
            let isHome = match.homeTeamId == teamId
            guard isHome || match.awayTeamId == teamId else { continue }
            let (mine, theirs) = isHome ? (home, away) : (away, home)
            played += 1
            goalsFor += mine
            goalsAgainst += theirs
            if mine > theirs { wins += 1 } else if mine == theirs { draws += 1 } else { losses += 1 }
        }
    }

    /// Whole-number win percentage, 0 when nothing played.
    public var winPercentage: Int { played == 0 ? 0 : Int((Double(wins) / Double(played) * 100).rounded()) }
}

extension APIClient {
    public func profile() async throws -> MyProfile {
        let envelope: ProfileEnvelope = try await get("/api/auth/me")
        return envelope.profile
    }

    public func myStats(seasonId: Int?) async throws -> PlayerStatsResponse {
        try await get("/api/me/player-stats", query: ["season_id": seasonId.map(String.init)])
    }

    public func playerStats(playerId: Int, seasonId: Int?) async throws -> PlayerStatsResponse {
        try await get("/api/roster/\(playerId)/stats", query: ["season_id": seasonId.map(String.init)])
    }

    public func roster(teamId: Int, seasonId: Int) async throws -> [RosterPlayer] {
        let response: RosterResponse = try await get("/api/teams/\(teamId)/roster",
                                                     query: ["season_id": String(seasonId)])
        return response.roster
    }

    public func teamStats(teamId: Int, seasonId: Int?) async throws -> [TeamPlayerStats] {
        let response: TeamStatsResponse = try await get("/api/teams/\(teamId)/stats",
                                                        query: ["season_id": seasonId.map(String.init)])
        return response.players
    }

    public func goalLeaders(seasonId: Int, ageGroupId: Int?, leagueId: Int?, divisionId: Int?,
                            limit: Int = 50) async throws -> [LeaderboardEntry] {
        try await get("/api/leaderboards/goals", query: [
            "season_id": String(seasonId), "age_group_id": ageGroupId.map(String.init),
            "league_id": leagueId.map(String.init), "division_id": divisionId.map(String.init),
            "limit": String(limit),
        ])
    }
}
