import Foundation
import Testing
@testable import MTKit

@Suite struct LineupTests {
    @Test func formationsMatchTheWebConfig() {
        #expect(Formation.layouts["4-3-3"]?.count == 11)
        #expect(Formation.layouts["4-3-3"]?.first == .init("GK", 50, 90))
        #expect(Formation.layouts["2-2"]?.count == 5)
    }

    @Test func placesKnownPositionsAndListsTheRest() throws {
        let data = json("""
        {"id": 1, "match_id": 5, "team_id": 7, "formation_name": "4-3-3", "positions": [
          {"player_id": 1, "position": "GK", "jersey_number": 25, "first_name": "Lucas", "last_name": "S", "display_name": "Lucas S"},
          {"player_id": 2, "position": "ST", "jersey_number": 9, "display_name": ""},
          {"player_id": 3, "position": "SWEEPER", "jersey_number": 4, "display_name": "Old School"}]}
        """)
        let lineup = try JSONDecoder.mt.decode(Lineup.self, from: data)
        let placed = lineup.placed()
        #expect(placed.onPitch.map(\.entry.label) == ["Lucas S", "#9"])
        #expect(placed.onPitch.first?.y == 90)
        #expect(placed.unplaced.map(\.position) == ["SWEEPER"])
    }

    @Test func nullBodyMeansNoLineup() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(AuthTokens(accessToken: "t", refreshToken: "r"))) { _ in
            (200, json("null"))
        }
        let lineup = try await client.lineup(matchId: 1, teamId: 2)
        #expect(lineup == nil)
    }
}
