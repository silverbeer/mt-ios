import Foundation

/// Formation layouts, generated from the web's frontend/src/config/formations.js
/// (11v11 and futsal). Coordinates are percentages: x 0 = left … 100 = right,
/// y 0 = attacking end … 100 = own goal.
public enum Formation {
    public struct Slot: Sendable, Equatable {
        public var position: String
        public var x: Double
        public var y: Double

        init(_ position: String, _ x: Double, _ y: Double) {
            self.position = position
            self.x = x
            self.y = y
        }
    }

    public static let layouts: [String: [Slot]] = [
        "4-3-3": [.init("GK", 50, 90), .init("LB", 15, 70), .init("LCB", 35, 75), .init("RCB", 65, 75), .init("RB", 85, 70), .init("LCM", 30, 50), .init("CDM", 50, 55), .init("RCM", 70, 50), .init("LW", 20, 25), .init("ST", 50, 20), .init("RW", 80, 25)],
        "4-4-2": [.init("GK", 50, 90), .init("LB", 15, 70), .init("LCB", 35, 75), .init("RCB", 65, 75), .init("RB", 85, 70), .init("LM", 15, 50), .init("LCM", 38, 50), .init("RCM", 62, 50), .init("RM", 85, 50), .init("LST", 38, 22), .init("RST", 62, 22)],
        "3-5-2": [.init("GK", 50, 90), .init("LCB", 25, 75), .init("CB", 50, 78), .init("RCB", 75, 75), .init("LWB", 10, 55), .init("LCM", 30, 50), .init("CDM", 50, 55), .init("RCM", 70, 50), .init("RWB", 90, 55), .init("LST", 38, 22), .init("RST", 62, 22)],
        "4-2-3-1": [.init("GK", 50, 90), .init("LB", 15, 70), .init("LCB", 35, 75), .init("RCB", 65, 75), .init("RB", 85, 70), .init("LCDM", 38, 58), .init("RCDM", 62, 58), .init("LW", 20, 38), .init("CAM", 50, 35), .init("RW", 80, 38), .init("ST", 50, 18)],
        "4-1-4-1": [.init("GK", 50, 90), .init("LB", 15, 70), .init("LCB", 35, 75), .init("RCB", 65, 75), .init("RB", 85, 70), .init("CDM", 50, 60), .init("LM", 15, 42), .init("LCM", 38, 42), .init("RCM", 62, 42), .init("RM", 85, 42), .init("ST", 50, 18)],
        "5-3-2": [.init("GK", 50, 90), .init("LWB", 10, 65), .init("LCB", 30, 75), .init("CB", 50, 78), .init("RCB", 70, 75), .init("RWB", 90, 65), .init("LCM", 30, 48), .init("CM", 50, 52), .init("RCM", 70, 48), .init("LST", 38, 22), .init("RST", 62, 22)],
        "3-4-3": [.init("GK", 50, 90), .init("LCB", 25, 75), .init("CB", 50, 78), .init("RCB", 75, 75), .init("LM", 15, 50), .init("LCM", 38, 52), .init("RCM", 62, 52), .init("RM", 85, 50), .init("LW", 20, 25), .init("ST", 50, 20), .init("RW", 80, 25)],
        "1-2-2": [.init("GK", 50, 90), .init("LD", 30, 65), .init("RD", 70, 65), .init("LF", 30, 35), .init("RF", 70, 35)],
        "2-2": [.init("GK", 50, 90), .init("LD", 25, 65), .init("RD", 75, 65), .init("LF", 25, 30), .init("RF", 75, 30)],
        "1-2-1": [.init("GK", 50, 90), .init("FIX", 50, 68), .init("LW", 22, 48), .init("RW", 78, 48), .init("PIV", 50, 25)],
        "3-1": [.init("GK", 50, 90), .init("LD", 25, 65), .init("CD", 50, 68), .init("RD", 75, 65), .init("PIV", 50, 30)],
    ]
}

/// A team's lineup for a match, from /api/matches/{id}/lineup/{team_id}.
public struct Lineup: Decodable, Sendable, Equatable {
    public struct Entry: Decodable, Sendable, Equatable, Hashable {
        public var playerId: Int?
        public var position: String
        public var jerseyNumber: Int?
        public var displayName: String?

        public var label: String { displayName?.isEmpty == false ? displayName! : jerseyNumber.map { "#\($0)" } ?? position }
    }

    public var formationName: String?
    public var positions: [Entry]?

    /// Players placed at their formation coordinates, plus any whose position the
    /// formation doesn't define (shown as a list by the UI).
    public func placed() -> (onPitch: [(entry: Entry, x: Double, y: Double)], unplaced: [Entry]) {
        let slots = formationName.flatMap { Formation.layouts[$0] } ?? []
        var onPitch: [(entry: Entry, x: Double, y: Double)] = []
        var unplaced: [Entry] = []
        for entry in positions ?? [] {
            if let slot = slots.first(where: { $0.position == entry.position }) {
                onPitch.append((entry, slot.x, slot.y))
            } else {
                unplaced.append(entry)
            }
        }
        return (onPitch, unplaced)
    }

    public var isEmpty: Bool { positions?.isEmpty ?? true }
}

extension APIClient {
    /// Nil when the team has no lineup for this match.
    public func lineup(matchId: Int, teamId: Int) async throws -> Lineup? {
        try await get("/api/matches/\(matchId)/lineup/\(teamId)")
    }
}
