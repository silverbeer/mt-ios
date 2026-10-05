import Foundation
import Testing
@testable import MTKit

@Suite struct PeopleTests {
    @Test func decodesMeProfileWithNestedTeamsAndPhotos() throws {
        let data = json("""
        {"success": true, "user": {"id": "u-1", "email": "g@x.y", "profile": {
          "username": "gabe35", "role": "team_player", "display_name": null, "first_name": "Gabe", "last_name": "S",
          "player_number": 35, "positions": ["CM", "CAM"], "photo_1_url": null, "photo_2_url": "https://p/2.jpg",
          "photo_3_url": null, "profile_photo_slot": 2, "primary_color": "#1E40AF",
          "club": null,
          "team": {"id": 7, "name": "Blues U15", "city": "X", "club": {"id": 3, "name": "Blues FC", "logo_url": "https://l"}},
          "current_teams": [{"team_id": 7, "team": {"id": 7, "name": "Blues U15", "club": {"id": 3, "name": "Blues FC"},
              "league": {"id": 1, "name": "Homegrown"}, "division": {"id": 4, "name": "Northeast"}},
            "season": {"id": 9, "name": "2026-2027"}, "age_group": {"id": 15, "name": "U15"},
            "league": null, "division": null}]}}}
        """)
        let profile = try JSONDecoder.mt.decode(ProfileEnvelope.self, from: data).profile
        #expect(profile.id == "u-1")
        #expect(profile.email == "g@x.y")
        #expect(profile.kind == .player)
        #expect(profile.fullName == "Gabe S")
        #expect(profile.profilePhotoUrl == "https://p/2.jpg")
        #expect(profile.displayClub?.name == "Blues FC")
        #expect(profile.currentTeams?.first?.subtitle == "U15 · Homegrown · Northeast")
    }

    @Test func roleSpellingsNormalize() {
        #expect(Role(raw: "club_manager") == .clubManager)
        #expect(Role(raw: "team-manager") == .teamManager)
        #expect(Role(raw: "club-fan") == .clubFan)
        #expect(Role(raw: nil) == .teamFan)
        #expect(!Role.teamFan.seesClubTeams)
        #expect(Role.clubFan.seesClubTeams)
    }

    @Test func statsFallbackWithoutAssistsDecodesZeros() throws {
        let data = json(#"{"player_id": 5, "season_id": 9, "stats": {"games_played": 3, "games_started": 2, "total_minutes": 120, "total_goals": 1}, "linked": true}"#)
        let response = try JSONDecoder.mt.decode(PlayerStatsResponse.self, from: data)
        #expect(response.stats == SeasonStats(gamesPlayed: 3, gamesStarted: 2, totalMinutes: 120, totalGoals: 1))
        #expect(response.linked == true)
    }

    @Test func rosterNamesAndPhotos() throws {
        let data = json("""
        {"success": true, "roster": [
          {"id": 1, "jersey_number": 9, "first_name": "Sam", "last_name": "Lee", "display_name": "Sammy",
           "has_account": true, "user_profile": {"id": "u", "photo_1_url": "https://a", "profile_photo_slot": 1}},
          {"id": 2, "jersey_number": 4, "first_name": null, "last_name": null, "display_name": null, "user_profile": null}]}
        """)
        let roster = try JSONDecoder.mt.decode(RosterResponse.self, from: data).roster
        let names: [String] = roster.map(\.name)
        #expect(names == ["Sammy", "#4"])
        #expect(roster[0].photoUrl == "https://a")
        #expect(roster[1].photoUrl == nil)
    }

    @Test func teamRecordCountsOnlyFinishedScoredMatches() {
        func m(_ id: Int, _ home: Int, _ away: Int, _ hs: Int?, _ as_: Int?, _ status: String) -> Match {
            Match(id: id, matchDate: "d", homeTeamId: home, awayTeamId: away, homeTeamName: "", awayTeamName: "",
                  homeScore: hs, awayScore: as_, matchStatus: MatchStatus(rawValue: status))
        }
        let record = TeamRecord(teamId: 7, matches: [
            m(1, 7, 8, 2, 1, "completed"), m(2, 9, 7, 1, 1, "completed"), m(3, 7, 9, 0, 3, "completed"),
            m(4, 7, 8, nil, nil, "scheduled"), m(5, 7, 8, 1, 0, "live"),
        ])
        let counts: [Int] = [record.played, record.wins, record.draws, record.losses]
        #expect(counts == [3, 1, 1, 1])
        let goals: [Int] = [record.goalsFor, record.goalsAgainst]
        #expect(goals == [3, 5])
        #expect(record.winPercentage == 33)
    }

    @Test func leaderboardDecodes() throws {
        let data = json(#"[{"player_id": 3, "jersey_number": 10, "first_name": "Ana", "last_name": "B", "team_id": 7, "team_name": "Blues", "goals": 8, "games_played": 5, "rank": 1, "goals_per_game": 1.6}]"#)
        let rows = try JSONDecoder.mt.decode([LeaderboardEntry].self, from: data)
        #expect(rows.first?.name == "Ana B")
        #expect(rows.first?.goalsPerGame == 1.6)
    }
}

@Suite struct ClubTeamTests {
    @Test func decodesClubTeamsAndGroupsByAgeYoungestFirst() throws {
        let data = json("""
        [{"id": 1, "name": "Blues U15 HG", "city": "X", "league_name": "Homegrown", "age_group_name": "U15",
          "division_name": "Northeast", "match_count": 12, "player_count": 18, "age_groups": [{"id": 15, "name": "U15"}],
          "leagues": {"id": 1, "name": "Homegrown"}, "team_mappings": []},
         {"id": 2, "name": "Blues U13", "age_group_name": "U13", "league_name": "Flex", "division_name": "Empire"},
         {"id": 3, "name": "Blues U9", "age_group_name": "U9"},
         {"id": 4, "name": "Blues Misc"}]
        """)
        let teams = try JSONDecoder.mt.decode([ClubTeam].self, from: data)
        #expect(teams[0].subtitle == "Homegrown · Northeast")
        let groups: [String] = ClubTeam.byAgeGroup(teams).map(\.ageGroup)
        #expect(groups == ["U9", "U13", "U15", "Other"])
    }

    @Test func listsATeamUnderEveryAgeGroupItIsMappedTo() throws {
        let data = json("""
        [{"id": 1, "name": "IFA", "age_group_name": "U13",
          "age_groups": [{"id": 13, "name": "U13"}, {"id": 14, "name": "U14"}, {"id": 15, "name": "U15"}]},
         {"id": 2, "name": "IFA Academy", "age_group_name": "U13", "age_groups": [{"id": 13, "name": "U13"}]}]
        """)
        let teams = try JSONDecoder.mt.decode([ClubTeam].self, from: data)
        let groups = ClubTeam.byAgeGroup(teams).map { ($0.ageGroup, $0.teams.map(\.id)) }
        #expect(groups.map(\.0) == ["U13", "U14", "U15"])
        #expect(groups.map(\.1) == [[1, 2], [1], [1]])
    }

    @Test func ownTeamIdsPutThePrimaryTeamFirstWithoutDuplicates() throws {
        let data = json("""
        {"team_id": 7, "current_teams": [{"team_id": 9}, {"team_id": 7}, {"team": {"id": 11}}]}
        """)
        let profile = try JSONDecoder.mt.decode(MyProfile.self, from: data)
        #expect(profile.ownTeamIds == [7, 9, 11])
        #expect(try JSONDecoder.mt.decode(MyProfile.self, from: json("{}")).ownTeamIds.isEmpty)
    }

    @Test func ageGroupForTeamComesFromCurrentTeams() throws {
        let data = json("""
        {"team_id": 7, "current_teams": [{"team_id": 7, "age_group": {"id": 15, "name": "U15"}}]}
        """)
        let profile = try JSONDecoder.mt.decode(MyProfile.self, from: data)
        #expect(profile.ageGroup(forTeam: 7) == NamedRef(id: 15, name: "U15"))
        #expect(profile.ageGroup(forTeam: 8) == nil)
    }

    @Test func rosterNarrowsToAnAgeGroup() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(AuthTokens(accessToken: "t", refreshToken: "r"))) { request in
            #expect(request.url?.query?.contains("age_group_id=15") == true)
            #expect(request.url?.query?.contains("season_id=3") == true)
            return (200, json(#"{"success": true, "roster": []}"#))
        }
        _ = try await client.roster(teamId: 7, seasonId: 3, ageGroupId: 15)
    }

    @Test func playerAccountProfileIsNilWhenForbidden() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(AuthTokens(accessToken: "t", refreshToken: "r"))) { _ in
            (403, json(#"{"detail": "Not in your club"}"#))
        }
        let profile = try await client.playerAccountProfile(userId: "u-2")
        #expect(profile == nil)
    }
}

@Suite struct StatColumnTests {
    private func row(_ id: Int, _ name: String, goals: Int, assists: Int, gp: Int) -> TeamPlayerStats {
        TeamPlayerStats(playerId: id, jerseyNumber: id, firstName: name, lastName: nil, gamesPlayed: gp,
                        gamesStarted: 0, totalMinutes: 0, totalGoals: goals, totalAssists: assists,
                        totalYellowCards: 0, totalRedCards: 0)
    }

    @Test func sortsDescendingWithGoalsThenNameTiebreak() {
        let rows = [row(1, "Cy", goals: 1, assists: 3, gp: 5), row(2, "Al", goals: 4, assists: 3, gp: 5),
                    row(3, "Bo", goals: 4, assists: 0, gp: 7)]
        let byAssists: [Int] = StatColumn.assists.sort(rows).map(\.playerId)
        #expect(byAssists == [2, 1, 3])
        let byGoals: [Int] = StatColumn.goals.sort(rows).map(\.playerId)
        #expect(byGoals == [2, 3, 1])
        let byGP: [Int] = StatColumn.gp.sort(rows).map(\.playerId)
        #expect(byGP == [3, 2, 1])
    }
}

@Suite struct CustomizationTests {
    @Test func normalizesHandlesAndSendsSnakeCase() throws {
        var profile = MyProfile(id: "u")
        profile.positions = ["CM", "CAM"]
        profile.primaryColor = "#112233"
        var custom = ProfileCustomization(from: profile)
        custom.instagramHandle = "@gabe.35"
        custom.tiktokHandle = "  "
        let body = try JSONSerialization.jsonObject(with: JSONEncoder.mt.encode(custom.normalized)) as? [String: Any]
        #expect(body?["instagram_handle"] as? String == "gabe.35")
        #expect(body?["tiktok_handle"] == nil)
        #expect(body?["primary_color"] as? String == "#112233")
        #expect(body?["positions"] as? [String] == ["CM", "CAM"])
        #expect(body?["player_number"] == nil)
    }

    @Test func handleValidationMatchesBackend() {
        #expect(ProfileCustomization.isValidHandle("gabe_35.x"))
        #expect(ProfileCustomization.isValidHandle(nil))
        #expect(!ProfileCustomization.isValidHandle("bad handle"))
        #expect(!ProfileCustomization.isValidHandle(String(repeating: "a", count: 31)))
        #expect(!ProfileCustomization.isValidHandle("émile"))
    }

    @Test func decodesPositionOptions() throws {
        let options = try JSONDecoder.mt.decode([PositionOption].self, from: json(
            #"[{"full_name": "Goalkeeper", "abbreviation": "GK", "group": "Goalkeeper"}]"#))
        #expect(options.first?.id == "GK")
    }
}
