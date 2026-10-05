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
