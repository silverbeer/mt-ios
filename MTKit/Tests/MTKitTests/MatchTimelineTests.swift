import Foundation
import Testing
@testable import MTKit

private func event(_ id: Int, _ type: String, team: Int? = nil, minute: Int? = nil, extra: Int? = nil,
                   created: String = "2026-10-04T14:00:00Z", player: String? = nil) -> MatchEvent {
    MatchEvent(id: id, matchId: 1, eventType: type, teamId: team, playerName: player, assistPlayerName: nil,
               matchMinute: minute, extraTime: extra, message: nil, createdAt: created)
}

private func live(kickoff: String? = "2026-10-04T14:00:00Z", halftime: String? = nil, second: String? = nil,
                  end: String? = nil, half: Int? = 40) -> LiveMatchState {
    LiveMatchState(matchId: 1, matchStatus: .live, homeScore: 0, awayScore: 0, kickoffTime: kickoff,
                   halftimeStart: halftime, secondHalfStart: second, matchEndTime: end, halfDuration: half,
                   homeTeamId: 1, homeTeamName: "H", awayTeamId: 2, awayTeamName: "A", recentEvents: nil)
}

private func at(_ s: String) -> Date { MTDate.timestamp(s)! }

@Suite struct MatchTimelineTests {
    @Test func splitsGoalsAndCardsByTeamInMinuteOrder() {
        let timeline = MatchTimeline(events: [
            event(1, "goal", team: 1, minute: 30),
            event(2, "goal", team: 1, minute: 12),
            event(3, "yellow_card", team: 2, minute: 20),
            event(4, "goal", team: 2, minute: 45, extra: 2),
            event(5, "status_change"),
            event(6, "red_card", team: 1, minute: 70),
        ], homeTeamId: 1, awayTeamId: 2)
        #expect(timeline.homeGoals.map(\.id) == [2, 1])
        #expect(timeline.awayGoals.map(\.minuteLabel) == ["45+2'"])
        #expect(timeline.homeCards.map(\.id) == [6])
        #expect(timeline.awayCards.map(\.id) == [3])
    }

    @Test func timelineIsOldestFirstByCreation() {
        let timeline = MatchTimeline(events: [
            event(2, "goal", team: 1, minute: 5, created: "2026-10-04T14:05:00Z"),
            event(1, "status_change", created: "2026-10-04T14:00:00Z"),
        ], homeTeamId: 1, awayTeamId: 2)
        #expect(timeline.all.map(\.id) == [1, 2])
    }

    @Test func clockFirstHalf() {
        let reading = LiveClock.read(live(), now: at("2026-10-04T14:12:34Z"))
        #expect(reading.display == "12:34")
        #expect(reading.minute == 12)
    }

    @Test func clockFirstHalfStoppageTime() {
        let reading = LiveClock.read(live(), now: at("2026-10-04T14:42:00Z"))
        #expect(reading.minute == 40)
        #expect(reading.extraTime == 2)
    }

    @Test func clockHalfTimeAndSecondHalfContinuesFromHalfDuration() {
        #expect(LiveClock.read(live(halftime: "2026-10-04T14:41:00Z"), now: at("2026-10-04T14:45:00Z")).display == "HT")
        let second = LiveClock.read(live(halftime: "2026-10-04T14:41:00Z", second: "2026-10-04T14:50:00Z"),
                                    now: at("2026-10-04T14:55:00Z"))
        #expect(second.display == "45:00")
        #expect(second.minute == 45)
    }

    @Test func clockFullTimeAndNotStarted() {
        #expect(LiveClock.read(live(end: "2026-10-04T15:40:00Z")).display == "FT")
        #expect(LiveClock.read(live(kickoff: nil)).display == "—")
    }

    @Test func liveScoredFlag() {
        var match = Match(id: 1, matchDate: "d", homeTeamId: 1, awayTeamId: 2, homeTeamName: "H", awayTeamName: "A")
        #expect(!match.isLiveScored)
        match.scoringMode = "live"
        #expect(match.isLiveScored)
    }
}
