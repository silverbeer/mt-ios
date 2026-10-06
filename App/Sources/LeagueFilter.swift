import Foundation
import Observation
import MTKit

/// Season / age group / league / division selection shared by the Table and Matches tabs.
/// Choices are remembered across launches.
@MainActor @Observable
final class LeagueFilter {
    private(set) var seasons: [Season] = []
    private(set) var ageGroups: [AgeGroup] = []
    private(set) var leagues: [League] = []
    private(set) var divisions: [Division] = []
    private(set) var isLoaded = false

    var seasonId: Int? { didSet { save(seasonId, Keys.season) } }
    var ageGroupId: Int? { didSet { save(ageGroupId, Keys.ageGroup) } }
    var leagueId: Int? { didSet { save(leagueId, Keys.league) } }
    var divisionId: Int? { didSet { save(divisionId, Keys.division) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seasonId = defaults.object(forKey: Keys.season) as? Int
        ageGroupId = defaults.object(forKey: Keys.ageGroup) as? Int
        leagueId = defaults.object(forKey: Keys.league) as? Int
        divisionId = defaults.object(forKey: Keys.division) as? Int
    }

    var season: Season? { seasons.first { $0.id == seasonId } }
    var ageGroup: AgeGroup? { ageGroups.first { $0.id == ageGroupId } }
    var division: Division? { divisions.first { $0.id == divisionId } }

    /// Short label for the current selection, e.g. "U14 · Northeast".
    var summary: String {
        [ageGroup?.name, division?.name].compactMap { $0 }.joined(separator: " · ")
    }

    func load(using client: APIClient) async throws {
        async let seasons = client.seasons()
        async let ageGroups = client.ageGroups()
        async let leagues = client.leagues()
        self.seasons = try await seasons
        self.ageGroups = try await ageGroups
        let allLeagues = try await leagues
        self.leagues = allLeagues.filter { $0.isActive ?? true }
            .sorted { ($0.displayOrder ?? .max, $0.name) < ($1.displayOrder ?? .max, $1.name) }
        LeagueFilter.reconcile(&seasonId, with: self.seasons.map(\.id),
                               fallback: self.seasons.first { $0.isCurrent == true }?.id ?? self.seasons.first?.id)
        LeagueFilter.reconcile(&ageGroupId, with: self.ageGroups.map(\.id), fallback: self.ageGroups.first?.id)
        LeagueFilter.reconcile(&leagueId, with: self.leagues.map(\.id), fallback: self.leagues.first?.id)
        try await loadDivisions(using: client)
        isLoaded = true
    }

    /// Put the Table selection on the user's team.
    func apply(_ home: HomeFilter, using client: APIClient) async throws {
        if let id = home.ageGroupId, ageGroups.contains(where: { $0.id == id }) { ageGroupId = id }
        if let id = home.leagueId, leagues.contains(where: { $0.id == id }) { try await selectLeague(id, using: client) }
        if let id = home.divisionId, divisions.contains(where: { $0.id == id }) { divisionId = id }
    }

    func selectLeague(_ id: Int?, using client: APIClient) async throws {
        leagueId = id
        try await loadDivisions(using: client)
    }

    private func loadDivisions(using client: APIClient) async throws {
        divisions = leagueId == nil ? [] : try await client.divisions(leagueId: leagueId)
        LeagueFilter.reconcile(&divisionId, with: divisions.map(\.id), fallback: divisions.first?.id)
    }

    /// Keep a saved selection if it still exists, otherwise fall back.
    static func reconcile(_ selection: inout Int?, with ids: [Int], fallback: Int?) {
        if let current = selection, ids.contains(current) { return }
        selection = fallback
    }

    private func save(_ value: Int?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private enum Keys {
        static let season = "filter.season"
        static let ageGroup = "filter.ageGroup"
        static let league = "filter.league"
        static let division = "filter.division"
    }
}
