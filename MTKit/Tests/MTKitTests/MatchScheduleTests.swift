import Foundation
import Testing
@testable import MTKit

private func match(_ id: Int, _ date: String, _ status: String, score: (Int, Int)? = nil,
                   kickoff: String? = nil, home: Int = 1, away: Int = 2) -> Match {
    Match(id: id, matchDate: date, scheduledKickoff: kickoff, homeTeamId: home, awayTeamId: away,
          homeTeamName: "H\(home)", awayTeamName: "A\(away)", homeScore: score?.0, awayScore: score?.1,
          matchStatus: MatchStatus(rawValue: status))
}

@Suite struct MatchScheduleTests {
    @Test func splitsLiveResultsAndFixtures() {
        let schedule = MatchSchedule([
            match(1, "2026-09-27", "completed", score: (2, 1)),
            match(2, "2026-10-04", "live", score: (0, 0)),
            match(3, "2026-10-11", "scheduled"),
            match(4, "2026-09-20", "forfeit", score: (3, 0)),
            match(5, "2026-10-04", "postponed"),
        ])
        #expect(schedule.live.map(\.id) == [2])
        #expect(schedule.results.map(\.date) == ["2026-09-27", "2026-09-20"])
        #expect(schedule.fixtures.map(\.date) == ["2026-10-04", "2026-10-11"])
        #expect(!schedule.isEmpty)
    }

    @Test func sortsWithinDayByKickoff() {
        let schedule = MatchSchedule([
            match(1, "2026-10-11", "scheduled", kickoff: "2026-10-11T15:00:00Z"),
            match(2, "2026-10-11", "scheduled", kickoff: "2026-10-11T09:00:00Z"),
        ])
        #expect(schedule.fixtures.first?.matches.map(\.id) == [2, 1])
    }

    @Test func involvingFiltersByEitherSide() {
        let all = [match(1, "d", "scheduled", home: 7, away: 8), match(2, "d", "scheduled", home: 9, away: 7),
                   match(3, "d", "scheduled", home: 1, away: 2)]
        #expect(MatchSchedule.involving([7], in: all).map(\.id) == [1, 2])
    }

    @Test func weekViewIsLiveThenDaysAscending() {
        let schedule = MatchSchedule.week([
            match(1, "2026-10-11", "scheduled"),
            match(2, "2026-10-05", "completed", score: (1, 0)),
            match(3, "2026-10-07", "live", score: (0, 0)),
            match(4, "2026-10-07", "completed", score: (2, 2)),
        ])
        #expect(schedule.live.map(\.id) == [3])
        #expect(schedule.fixtures.map(\.date) == ["2026-10-05", "2026-10-07", "2026-10-11"])
        #expect(schedule.results.isEmpty)
    }

    @Test func emptyInputIsEmpty() {
        #expect(MatchSchedule([]).isEmpty)
    }

    @Test func parsesTimestampsWithAndWithoutFraction() {
        #expect(MTDate.timestamp("2026-10-04T14:00:00Z") != nil)
        #expect(MTDate.timestamp("2026-10-04T14:00:00.123456+00:00") != nil)
        #expect(MTDate.date(fromDay: "2026-10-04").map(MTDate.dayString) == "2026-10-04")
    }
}
