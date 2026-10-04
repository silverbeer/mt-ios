import Foundation
import Testing
@testable import MTKit

@Suite struct ModelDecodingTests {
    @Test func decodesTableResponseIgnoringExtraFields() throws {
        let data = json("""
        {"has_qop_data": false, "qop_week_of": null, "coverage": {},
         "standings": [{"team": "Blues", "team_id": 7, "club_id": 3, "logo_url": null,
           "played": 5, "wins": 4, "draws": 1, "losses": 0, "goals_for": 12, "goals_against": 3,
           "goal_difference": 9, "points": 13, "shootout_wins": 0, "shootout_losses": 0,
           "form": ["W","W","D","W","W"], "position_change": 1, "qop_rank": null, "qop_rank_change": null}]}
        """)
        let table = try JSONDecoder.mt.decode(TableResponse.self, from: data)
        #expect(table.standings.count == 1)
        let row = table.standings[0]
        #expect(row.teamId == 7)
        #expect(row.goalDifference == 9)
        #expect(row.form == ["W", "W", "D", "W", "W"])
        #expect(row.id == "7")
    }

    @Test func decodesMatchWithNullScoresAndUnknownStatus() throws {
        let data = json("""
        {"id": 42, "match_date": "2026-10-04", "scheduled_kickoff": "2026-10-04T14:00:00+00:00",
         "home_team_id": 1, "away_team_id": 2, "home_team_name": "A", "away_team_name": "B",
         "home_score": null, "away_score": null, "match_status": "abandoned",
         "home_team_club": {"id": 9, "name": "Club A", "logo_url": "https://x/y.png"},
         "red_cards": [], "yellow_cards": []}
        """)
        let match = try JSONDecoder.mt.decode(Match.self, from: data)
        #expect(match.id == 42)
        #expect(!match.hasScore)
        #expect(match.status == .unknown("abandoned"))
        #expect(match.homeTeamClub?.logoUrl == "https://x/y.png")
    }

    @Test func matchStatusFinality() {
        #expect(MatchStatus(rawValue: "completed").isFinal)
        #expect(MatchStatus(rawValue: "forfeit").isFinal)
        #expect(!MatchStatus(rawValue: "live").isFinal)
        #expect(MatchStatus(rawValue: "live").rawValue == "live")
    }

    @Test func decodesLiveStateWithEvents() throws {
        let data = json("""
        {"match_id": 5, "match_status": "live", "home_score": 1, "away_score": 0,
         "kickoff_time": "2026-10-04T14:00:05Z", "half_duration": 40,
         "recent_events": [{"id": 1, "match_id": 5, "event_type": "goal", "team_id": 1,
           "player_name": "Sam", "match_minute": 12, "extra_time": null, "message": "Goal!",
           "created_at": "2026-10-04T14:12:00Z"}]}
        """)
        let live = try JSONDecoder.mt.decode(LiveMatchState.self, from: data)
        #expect(live.matchStatus == .live)
        #expect(live.halfDuration == 40)
        #expect(live.recentEvents?.first?.playerName == "Sam")
    }
}
