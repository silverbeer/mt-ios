import Foundation
import Observation
import MTKit

/// Matches-tab division selection: any number of divisions across leagues, empty = all.
/// Saved so the same selection is applied the next time the app opens. Season and
/// age group come from the shared LeagueFilter.
@MainActor @Observable
final class MatchesFilterStore {
    private(set) var groups: [MatchFilter.LeagueGroup] = []
    private(set) var isLoaded = false

    var divisionIds: Set<Int> {
        didSet { defaults.set(Array(divisionIds).sorted(), forKey: Self.key) }
    }

    private let defaults: UserDefaults
    static let key = "matches.divisionIds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        divisionIds = Set(defaults.array(forKey: Self.key) as? [Int] ?? [])
    }

    func load(using client: APIClient, leagues: [League]) async throws {
        let divisions = try await client.divisions()
        groups = MatchFilter.groups(divisions: divisions, leagues: leagues)
        isLoaded = true
    }

    func toggle(_ id: Int) {
        if divisionIds.contains(id) { divisionIds.remove(id) } else { divisionIds.insert(id) }
    }

    /// League header action: select the whole league, or clear it if already fully selected.
    func toggleLeague(_ group: MatchFilter.LeagueGroup) {
        let ids = Set(group.divisions.map(\.id))
        if ids.isSubset(of: divisionIds) { divisionIds.subtract(ids) } else { divisionIds.formUnion(ids) }
    }

    func isWholeLeagueSelected(_ group: MatchFilter.LeagueGroup) -> Bool {
        Set(group.divisions.map(\.id)).isSubset(of: divisionIds)
    }

    /// "All divisions", "Northeast", or "3 divisions".
    var summary: String {
        switch divisionIds.count {
        case 0: return "All divisions"
        case 1:
            let id = divisionIds.first!
            return groups.flatMap(\.divisions).first { $0.id == id }?.name ?? "1 division"
        default: return "\(divisionIds.count) divisions"
        }
    }
}
