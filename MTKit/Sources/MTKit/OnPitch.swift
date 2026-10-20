import Foundation

/// Who is on the pitch now, by position (SB-1359) — the Android `OnPitch` rules.
///
/// The saved lineup is the starting XI and is never rewritten mid-match;
/// substitutions and position changes are events applied on top, oldest first. An
/// incoming player takes the slot of the player they replaced; a player moving into
/// an occupied slot swaps with whoever is there. An event naming a player who isn't
/// on the pitch is ignored rather than guessed at.
public enum OnPitch {
    public static func current(_ starting: [String: Int], events: [MatchEvent]) -> [String: Int] {
        var slots = starting
        func slot(of id: Int) -> String? { slots.first { $0.value == id }?.key }
        let ordered = events.sorted { ($0.createdAt ?? "", $0.id) < ($1.createdAt ?? "", $1.id) }
        for event in ordered {
            switch event.eventType {
            case "substitution":
                guard let out = event.playerOutId, let inn = event.playerId,
                      let position = slot(of: out) else { continue }
                slots[position] = inn
            case "position_change":
                guard let id = event.playerId, let to = event.position,
                      let from = slot(of: id), from != to else { continue }
                let other = slots[to]
                slots[to] = id
                slots[from] = other
            default:
                continue
            }
        }
        return slots
    }
}

extension Lineup {
    /// This lineup with the match's subs and position changes applied. Players who
    /// came on aren't in the saved lineup, so their number and name come from
    /// `roster`; slots without a player are kept as they were.
    public func current(events: [MatchEvent], roster: [RosterPlayer] = []) -> Lineup {
        guard let positions, !events.isEmpty else { return self }
        let starters = positions.compactMap { e in e.playerId.map { (e.position, $0) } }
        let now = OnPitch.current(Dictionary(starters, uniquingKeysWith: { a, _ in a }), events: events)
        let known = Dictionary(positions.compactMap { e in e.playerId.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        let squad = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var placed = positions.filter { $0.playerId == nil && now[$0.position] == nil }
        for entry in positions {
            guard let id = now[entry.position] else { continue }
            placed.append(Self.entry(id, at: entry.position, known: known, squad: squad))
        }
        // A move to a slot the saved lineup never had.
        for (position, id) in now where !positions.contains(where: { $0.position == position }) {
            placed.append(Self.entry(id, at: position, known: known, squad: squad))
        }
        var copy = self
        copy.positions = placed
        return copy
    }

    private static func entry(_ id: Int, at position: String, known: [Int: Entry],
                              squad: [Int: RosterPlayer]) -> Entry {
        if var e = known[id] {
            e.position = position
            return e
        }
        let p = squad[id]
        return Entry(playerId: id, position: position, jerseyNumber: p?.jerseyNumber, displayName: p?.name)
    }
}
