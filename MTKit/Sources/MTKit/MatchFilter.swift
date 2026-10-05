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
}
