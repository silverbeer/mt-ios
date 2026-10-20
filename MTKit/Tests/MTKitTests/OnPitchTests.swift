import Foundation
import Testing
@testable import MTKit

private func sub(_ id: Int, out: Int, on: Int, at created: String = "2026-10-04T14:30:00Z") -> MatchEvent {
    MatchEvent(id: id, matchId: 1, eventType: "substitution", teamId: 1, playerName: nil, assistPlayerName: nil,
               matchMinute: nil, extraTime: nil, message: nil, createdAt: created, playerId: on, playerOutId: out)
}

private func move(_ id: Int, player: Int, to position: String, at created: String = "2026-10-04T14:30:00Z") -> MatchEvent {
    MatchEvent(id: id, matchId: 1, eventType: "position_change", teamId: 1, playerName: nil, assistPlayerName: nil,
               matchMinute: nil, extraTime: nil, message: nil, createdAt: created, playerId: player, position: position)
}

@Suite struct OnPitchTests {
    // The match that prompted SB-1352: Sebby (20) on for Jack (9, ST), Josh (7) RW -> ST.
    let front = ["GK": 1, "RW": 7, "ST": 9]

    @Test func noEventsIsTheStartingXI() {
        #expect(OnPitch.current(front, events: []) == front)
    }

    @Test func subThenReshuffle() {
        let events = [sub(1, out: 9, on: 20), move(2, player: 7, to: "ST"), move(3, player: 20, to: "RW")]
        #expect(OnPitch.current(front, events: events) == ["GK": 1, "RW": 20, "ST": 7])
    }

    @Test func appliesOldestFirstWhateverTheInputOrder() {
        // Newest first, as the API returns recent events.
        let events = [move(2, player: 7, to: "ST", at: "2026-10-04T14:31:00Z"), sub(1, out: 9, on: 20)]
        #expect(OnPitch.current(front, events: events) == ["GK": 1, "RW": 20, "ST": 7])
    }

    @Test func moveIntoOccupiedSlotSwaps() {
        #expect(OnPitch.current(front, events: [move(1, player: 1, to: "ST")]) == ["GK": 9, "RW": 7, "ST": 1])
    }

    @Test func eventsForPlayersOffThePitchAreIgnored() {
        #expect(OnPitch.current(front, events: [sub(1, out: 77, on: 20)]) == front)
        #expect(OnPitch.current(front, events: [move(1, player: 77, to: "ST")]) == front)
    }

    @Test func lineupTakesSubsNamesFromTheRoster() throws {
        let lineup = Lineup(formationName: "4-3-3", positions: [
            .init(playerId: 1, position: "GK", jerseyNumber: 1, displayName: "Keeper"),
            .init(playerId: 7, position: "RW", jerseyNumber: 7, displayName: "Josh"),
            .init(playerId: 9, position: "ST", jerseyNumber: 9, displayName: "Jack"),
        ])
        let roster = try JSONDecoder.mt.decode([RosterPlayer].self, from: Data("""
            [{"id": 20, "jersey_number": 20, "display_name": "Sebby"}]
            """.utf8))
        let now = lineup.current(events: [sub(1, out: 9, on: 20), move(2, player: 7, to: "ST")], roster: roster)
        let byPosition = Dictionary(uniqueKeysWithValues: (now.positions ?? []).map { ($0.position, $0) })
        #expect(byPosition["ST"]?.displayName == "Josh")
        #expect(byPosition["RW"]?.displayName == "Sebby")
        #expect(byPosition["RW"]?.jerseyNumber == 20)
        #expect(byPosition["GK"]?.displayName == "Keeper")
        #expect(now.positions?.count == 3)
    }
}
