import Foundation

/// Client-side filter for the Matches tab: one age group, any number of divisions
/// across leagues. Mirrors the Android conference filter (domain/Conferences.kt):
/// an empty division set means "all divisions".
public struct MatchFilter: Sendable, Equatable {
    public var ageGroupId: Int?
    public var divisionIds: Set<Int>

    public init(ageGroupId: Int? = nil, divisionIds: Set<Int> = []) {
        self.ageGroupId = ageGroupId
        self.divisionIds = divisionIds
    }

    public func apply(to matches: [Match]) -> [Match] {
        matches.filter { match in
            (ageGroupId == nil || match.ageGroupId == ageGroupId)
                && (divisionIds.isEmpty || match.divisionId.map(divisionIds.contains) == true)
        }
    }

    /// Divisions grouped under their league for the picker, leagues in the given order
    /// and divisions alphabetically. Divisions whose league isn't listed go under "Other".
    public struct LeagueGroup: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var divisions: [Division]

        public init(id: String, title: String, divisions: [Division]) {
            self.id = id
            self.title = title
            self.divisions = divisions
        }
    }

    public static func groups(divisions: [Division], leagues: [League]) -> [LeagueGroup] {
        var groups = leagues.compactMap { league -> LeagueGroup? in
            let members = divisions.filter { $0.leagueId == league.id }.sorted { $0.name < $1.name }
            return members.isEmpty ? nil : LeagueGroup(id: "league-\(league.id)", title: league.name, divisions: members)
        }
        let known = Set(leagues.map(\.id))
        let other = divisions.filter { $0.leagueId.map { !known.contains($0) } ?? true }.sorted { $0.name < $1.name }
        if !other.isEmpty { groups.append(LeagueGroup(id: "other", title: "Other", divisions: other)) }
        return groups
    }

    /// Competitions played inside a division (backend DIVISION_SCOPED_MATCH_TYPES). Flex
    /// matches sit in a Flex-league bracket, separate from the team's Homegrown division.
    public static let divisionScopedCompetitions: Set<String> = ["League", "Flex"]

    /// Where a player's filters start: their team's age group and league, and the divisions
    /// their team plays League and Flex matches in (the profile only names the Homegrown
    /// division; the Flex bracket comes from the schedule). Nil without a team id.
    public static func home(for team: CurrentTeam, schedule: [Match]) -> HomeFilter? {
        guard let teamId = team.teamId ?? team.team?.id else { return nil }
        let ageGroupId = team.ageGroup?.id
        var divisionIds = Set([team.division?.id ?? team.team?.division?.id].compactMap { $0 })
        for match in schedule where match.homeTeamId == teamId || match.awayTeamId == teamId {
            guard ageGroupId == nil || match.ageGroupId == ageGroupId,
                  let type = match.matchTypeName, divisionScopedCompetitions.contains(type),
                  let division = match.divisionId else { continue }
            divisionIds.insert(division)
        }
        return HomeFilter(teamId: teamId, ageGroupId: ageGroupId,
                          leagueId: team.league?.id ?? team.team?.league?.id,
                          divisionId: team.division?.id ?? team.team?.division?.id, divisionIds: divisionIds)
    }
}

/// A player's starting filters (see `MatchFilter.home`).
public struct HomeFilter: Sendable, Equatable {
    public var teamId: Int
    public var ageGroupId: Int?
    /// The team's own league and division, for the Table tab's single selection.
    public var leagueId: Int?
    public var divisionId: Int?
    /// Every division the team plays League or Flex in, for the Matches tab.
    public var divisionIds: Set<Int>

    public init(teamId: Int, ageGroupId: Int?, leagueId: Int?, divisionId: Int?, divisionIds: Set<Int>) {
        self.teamId = teamId
        self.ageGroupId = ageGroupId
        self.leagueId = leagueId
        self.divisionId = divisionId
        self.divisionIds = divisionIds
    }
}
