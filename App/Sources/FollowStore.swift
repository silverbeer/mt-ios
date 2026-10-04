import Foundation
import Observation
import MTKit

/// The signed-in user's followed teams. Follows decide which score updates get pushed.
@MainActor @Observable
final class FollowStore {
    private(set) var teams: [FollowedTeam] = []
    private(set) var isLoaded = false
    /// Called after a successful follow — the app uses it to ask for notification permission.
    var onFirstFollow: (() -> Void)?

    var teamIds: Set<Int> { Set(teams.map(\.teamId)) }

    func isFollowing(_ teamId: Int) -> Bool { teamIds.contains(teamId) }

    func load(using client: APIClient) async throws {
        teams = try await client.follows()
        isLoaded = true
    }

    func toggle(_ team: TeamRoute, using client: APIClient) async throws {
        if isFollowing(team.id) {
            teams.removeAll { $0.teamId == team.id }
            do {
                try await client.unfollow(teamId: team.id)
            } catch {
                try? await load(using: client)
                throw error
            }
        } else {
            teams.insert(FollowedTeam(teamId: team.id, team: .init(id: team.id, name: team.name)), at: 0)
            do {
                try await client.follow(teamId: team.id)
            } catch {
                try? await load(using: client)
                throw error
            }
            onFirstFollow?()
            try? await load(using: client)
        }
    }

    func reset() {
        teams = []
        isLoaded = false
    }
}
