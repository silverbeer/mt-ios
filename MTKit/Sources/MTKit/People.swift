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
    public var instagramHandle: String?
    public var snapchatHandle: String?
    public var tiktokHandle: String?

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

    /// The age group the user plays in for one of their teams ("U15" for a Homegrown squad
    /// that spans U13–U15), from `current_teams`.
    public func ageGroup(forTeam teamId: Int) -> NamedRef? {
        currentTeams?.first { ($0.teamId ?? $0.team?.id) == teamId }?.ageGroup
    }

    /// The current-team entry for the primary team, else the first (web SB-599 personalizes
    /// its age group / league / division defaults from it).
    public var primaryTeam: CurrentTeam? {
        let primary = teamId ?? team?.id
        return currentTeams?.first { primary != nil && ($0.teamId ?? $0.team?.id) == primary } ?? currentTeams?.first
    }

    /// The user's own teams: the primary team first, then the rest of `current_teams`.
    public var ownTeamIds: [Int] {
        var ids: [Int] = []
        for id in [teamId ?? team?.id] + (currentTeams ?? []).map({ $0.teamId ?? $0.team?.id }) {
            if let id, !ids.contains(id) { ids.append(id) }
        }
        return ids
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

    /// `ageGroupId` narrows a squad that spans age groups to that age group's players.
    public func roster(teamId: Int, seasonId: Int, ageGroupId: Int? = nil) async throws -> [RosterPlayer] {
        let response: RosterResponse = try await get("/api/teams/\(teamId)/roster", query: [
            "season_id": String(seasonId), "age_group_id": ageGroupId.map(String.init),
        ])
        return response.roster
    }

    public func teamStats(teamId: Int, seasonId: Int?, matchTypeId: Int? = nil) async throws -> [TeamPlayerStats] {
        let response: TeamStatsResponse = try await get("/api/teams/\(teamId)/stats", query: [
            "season_id": seasonId.map(String.init), "match_type_id": matchTypeId.map(String.init),
        ])
        return response.players
    }

    public func matchTypes() async throws -> [MatchType] { try await get("/api/match-types") }

    public func goalLeaders(seasonId: Int, ageGroupId: Int?, leagueId: Int?, divisionId: Int?,
                            limit: Int = 50) async throws -> [LeaderboardEntry] {
        try await get("/api/leaderboards/goals", query: [
            "season_id": String(seasonId), "age_group_id": ageGroupId.map(String.init),
            "league_id": leagueId.map(String.init), "division_id": divisionId.map(String.init),
            "limit": String(limit),
        ])
    }
}

/// A team in a club, from /api/clubs/{id}/teams.
public struct ClubTeam: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var city: String?
    public var leagueName: String?
    public var ageGroupName: String?
    public var divisionName: String?
    public var matchCount: Int?
    public var playerCount: Int?
    public var ageGroups: [NamedRef]?

    /// "Homegrown · Northeast".
    public var subtitle: String { [leagueName, divisionName].compactMap { $0 }.joined(separator: " · ") }

    /// Every age group the team plays in. `age_group_name` is only the first of these.
    public var ageGroupNames: [String] {
        let names = (ageGroups ?? []).compactMap(\.name)
        return names.isEmpty ? [ageGroupName ?? "Other"] : names
    }

    /// Club teams grouped by age group, youngest first ("U13" < "U14"); teams without one last.
    /// A team mapped to several age groups (a Homegrown squad across U13–U15) is listed under each.
    public static func byAgeGroup(_ teams: [ClubTeam]) -> [(ageGroup: String, teams: [ClubTeam])] {
        var groups: [String: [ClubTeam]] = [:]
        for team in teams {
            for ageGroup in team.ageGroupNames { groups[ageGroup, default: []].append(team) }
        }
        return groups
            .map { (ageGroup: $0.key, teams: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.ageGroup == "Other" { return false }
                if rhs.ageGroup == "Other" { return true }
                return lhs.ageGroup.localizedStandardCompare(rhs.ageGroup) == .orderedAscending
            }
    }
}

/// A club from /api/clubs.
public struct Club: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var logoUrl: String?
    public var primaryColor: String?
}

/// Another player's account profile, /api/players/{user_id}/profile (same club only).
public struct PlayerAccountProfile: Decodable, Sendable, Equatable {
    public var id: String?
    public var displayName: String?
    public var playerNumber: Int?
    public var positions: [String]?
    public var photo1Url: String?
    public var photo2Url: String?
    public var photo3Url: String?
    public var profilePhotoSlot: Int?
    public var primaryColor: String?
    public var textColor: String?

    public var photos: [String] { [photo1Url, photo2Url, photo3Url].compactMap { $0 } }
}

struct PlayerAccountEnvelope: Decodable, Sendable { var player: PlayerAccountProfile }

extension APIClient {
    public func clubTeams(clubId: Int) async throws -> [ClubTeam] {
        try await get("/api/clubs/\(clubId)/teams")
    }

    public func clubs() async throws -> [Club] { try await get("/api/clubs", query: ["include_teams": "false"]) }

    /// Nil when the viewer may not see it (different club → 403) or it doesn't exist.
    public func playerAccountProfile(userId: String) async throws -> PlayerAccountProfile? {
        do {
            let envelope: PlayerAccountEnvelope = try await get("/api/players/\(userId)/profile")
            return envelope.player
        } catch APIError.http(let status, _) where status == 403 || status == 404 {
            return nil
        }
    }
}

/// Competition type (League, Flex, Cup, …) from /api/match-types.
public struct MatchType: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var displayOrder: Int?
}

/// Sortable Golden Boot columns (web GoldenBoot.vue statColumns).
public enum StatColumn: String, CaseIterable, Sendable, Identifiable {
    case gp = "GP", gs = "GS", goals = "G", assists = "A", yellow = "YC", red = "RC"

    public var id: String { rawValue }

    public func value(_ row: TeamPlayerStats) -> Int {
        switch self {
        case .gp: row.gamesPlayed ?? 0
        case .gs: row.gamesStarted ?? 0
        case .goals: row.totalGoals ?? 0
        case .assists: row.totalAssists ?? 0
        case .yellow: row.totalYellowCards ?? 0
        case .red: row.totalRedCards ?? 0
        }
    }

    /// Highest first; ties broken by goals, then name, so the order is stable.
    public func sort(_ rows: [TeamPlayerStats]) -> [TeamPlayerStats] {
        rows.sorted { a, b in
            let (va, vb) = (value(a), value(b))
            if va != vb { return va > vb }
            let (ga, gb) = (a.totalGoals ?? 0, b.totalGoals ?? 0)
            if ga != gb { return ga > gb }
            return a.name < b.name
        }
    }
}

/// One choice in the position picker (/api/positions).
public struct PositionOption: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var fullName: String
    public var abbreviation: String
    public var group: String

    public var id: String { abbreviation }
}

/// Fields a player edits themselves (web PlayerProfileEditor). Jersey number is set
/// by the team manager and is not sent. Nil fields are left unchanged by the backend.
public struct ProfileCustomization: Encodable, Sendable, Equatable {
    public var overlayStyle: String?
    public var primaryColor: String?
    public var textColor: String?
    public var accentColor: String?
    public var positions: [String]?
    public var instagramHandle: String?
    public var snapchatHandle: String?
    public var tiktokHandle: String?

    public init(from profile: MyProfile) {
        overlayStyle = profile.overlayStyle
        primaryColor = profile.primaryColor
        textColor = profile.textColor
        accentColor = profile.accentColor
        positions = profile.positions
        instagramHandle = profile.instagramHandle
        snapchatHandle = profile.snapchatHandle
        tiktokHandle = profile.tiktokHandle
    }

    public static let overlayStyles = ["badge", "jersey", "caption", "none"]

    /// Handles as the backend accepts them: no leading @, empty → nil (web sends null).
    public var normalized: ProfileCustomization {
        var copy = self
        func clean(_ handle: String?) -> String? {
            let trimmed = handle?.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        copy.instagramHandle = clean(instagramHandle)
        copy.snapchatHandle = clean(snapchatHandle)
        copy.tiktokHandle = clean(tiktokHandle)
        return copy
    }

    /// Backend rule: letters, numbers, underscores, periods; at most 30.
    public static func isValidHandle(_ handle: String?) -> Bool {
        guard let handle, !handle.isEmpty else { return true }
        return handle.count <= 30 && handle.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            && handle.unicodeScalars.allSatisfy(\.isASCII)
    }
}

extension APIClient {
    public func positions() async throws -> [PositionOption] { try await get("/api/positions") }

    public func updateCustomization(_ customization: ProfileCustomization) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await send("PUT", "/api/auth/profile/customization", body: customization.normalized)
    }
}
