import Foundation
import Testing
@testable import MTKit

private func match(_ id: Int, age: Int?, division: Int?) -> Match {
    Match(id: id, matchDate: "2026-10-05", homeTeamId: 1, awayTeamId: 2, homeTeamName: "H", awayTeamName: "A",
          ageGroupId: age, divisionId: division)
}

@Suite struct MatchFilterTests {
    let matches = [match(1, age: 16, division: 10), match(2, age: 16, division: 20),
                   match(3, age: 15, division: 10), match(4, age: 16, division: nil)]

    @Test func emptyDivisionSetMeansAll() {
        #expect(MatchFilter(ageGroupId: 16).apply(to: matches).map(\.id) == [1, 2, 4])
    }

    @Test func multipleDivisionsAcrossLeagues() {
        let filter = MatchFilter(ageGroupId: 16, divisionIds: [10, 20])
        #expect(filter.apply(to: matches).map(\.id) == [1, 2])
    }

    @Test func noAgeGroupKeepsAllAges() {
        #expect(MatchFilter(divisionIds: [10]).apply(to: matches).map(\.id) == [1, 3])
    }

    @Test func groupsDivisionsUnderLeaguesInLeagueOrder() {
        let leagues = [League(id: 1, name: "Homegrown"), League(id: 2, name: "Flex")]
        let divisions = [Division(id: 21, name: "New England", leagueId: 2), Division(id: 11, name: "Northeast", leagueId: 1),
                         Division(id: 20, name: "Empire", leagueId: 2), Division(id: 99, name: "Mystery", leagueId: 7)]
        let groups = MatchFilter.groups(divisions: divisions, leagues: leagues)
        #expect(groups.map(\.title) == ["Homegrown", "Flex", "Other"])
        #expect(groups[1].divisions.map(\.name) == ["Empire", "New England"])
    }
}

@Suite struct CompetitionTests {
    @Test func namesMapToKindsCaseInsensitively() {
        #expect(Competition(name: "League") == .league)
        #expect(Competition(name: "flex") == .flex)
        #expect(Competition(name: "Tournament") == .tournament)
        #expect(Competition(name: "Friendly") == .friendly)
        #expect(Competition(name: "Cup") == .other("Cup"))
        #expect(Competition(name: "Cup")?.label == "CUP")
        #expect(Competition.flex.label == "FLEX")
    }

    @Test func unknownCompetitionGetsNoChip() {
        #expect(Competition(name: nil) == nil)
        #expect(Competition(name: "") == nil)
        #expect(Competition(name: " ") == nil)
        #expect(Competition(name: "Unknown") == nil)
        let match = Match(id: 1, matchDate: "2026-10-05", homeTeamId: 1, awayTeamId: 2, homeTeamName: "H",
                          awayTeamName: "A", matchTypeName: "Flex")
        #expect(match.competition == .flex)
    }
}

@Suite struct HomeFilterTests {
    private func game(_ id: Int, home: Int, away: Int, age: Int, division: Int?, type: String?) -> Match {
        Match(id: id, matchDate: "2026-10-05", homeTeamId: home, awayTeamId: away, homeTeamName: "H", awayTeamName: "A",
              ageGroupId: age, divisionId: division, matchTypeName: type)
    }

    private let u15 = CurrentTeam(teamId: 7, ageGroup: NamedRef(id: 15, name: "U15"),
                                  league: NamedRef(id: 1, name: "Homegrown"), division: NamedRef(id: 10, name: "Northeast"))

    @Test func homeAddsTheFlexBracketFromTheTeamsSchedule() {
        let schedule = [
            game(1, home: 7, away: 8, age: 15, division: 10, type: "League"),
            game(2, home: 9, away: 7, age: 15, division: 40, type: "Flex"),        // Flex bracket
            game(3, home: 7, away: 8, age: 13, division: 41, type: "Flex"),        // other age group
            game(4, home: 7, away: 8, age: 15, division: 42, type: "Friendly"),    // not division-scoped
            game(5, home: 8, away: 9, age: 15, division: 43, type: "League"),      // not our team
            game(6, home: 7, away: 8, age: 15, division: nil, type: "Flex"),
        ]
        let home = MatchFilter.home(for: u15, schedule: schedule)
        #expect(home == HomeFilter(teamId: 7, ageGroupId: 15, leagueId: 1, divisionId: 10, divisionIds: [10, 40]))
    }

    @Test func homeWithoutScheduleIsTheProfileDivision() {
        #expect(MatchFilter.home(for: u15, schedule: [])?.divisionIds == [10])
        #expect(MatchFilter.home(for: CurrentTeam(), schedule: []) == nil)
    }

    @Test func primaryTeamPrefersTheProfilesTeam() throws {
        let data = Data("""
        {"team_id": 7, "current_teams": [{"team_id": 3, "age_group": {"id": 13, "name": "U13"}},
                                          {"team_id": 7, "age_group": {"id": 15, "name": "U15"}}]}
        """.utf8)
        let profile = try JSONDecoder.mt.decode(MyProfile.self, from: data)
        #expect(profile.primaryTeam?.ageGroup?.id == 15)
        let noPrimary = try JSONDecoder.mt.decode(MyProfile.self, from: Data(#"{"current_teams": [{"team_id": 3}]}"#.utf8))
        #expect(noPrimary.primaryTeam?.teamId == 3)
    }
}
