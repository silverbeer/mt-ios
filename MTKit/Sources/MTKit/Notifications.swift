import Foundation

// Team follows, notification preferences and APNs device registration
// (backend api/push.py). Follows drive who receives score-update pushes.

public struct FollowedTeam: Codable, Sendable, Equatable, Identifiable, Hashable {
    public struct Team: Codable, Sendable, Equatable, Hashable {
        public struct Named: Codable, Sendable, Equatable, Hashable {
            public var id: Int?
            public var name: String?
        }
        public var id: Int?
        public var name: String?
        public var club: Named?
        public var division: Named?
    }

    public var teamId: Int
    public var createdAt: String?
    public var team: Team?

    public var id: Int { teamId }
    public var name: String { team?.name ?? "Team \(teamId)" }

    /// "Club · Division" — disambiguates teams named after their club.
    public var subtitle: String {
        [team?.club?.name, team?.division?.name].compactMap { $0 }.filter { $0 != name }.joined(separator: " · ")
    }

    public init(teamId: Int, createdAt: String? = nil, team: Team? = nil) {
        self.teamId = teamId
        self.createdAt = createdAt
        self.team = team
    }
}

struct FollowsResponse: Decodable, Sendable { var follows: [FollowedTeam] }
struct FollowRequest: Encodable, Sendable { var teamId: Int }
struct FollowResponse: Decodable, Sendable { var teamId: Int; var following: Bool }

/// Event types a user can opt in/out of, in display order.
public enum NotificationEvent: String, CaseIterable, Sendable, Identifiable {
    case kickoff, goal, halftime, fulltime
    case yellowCard = "yellow_card"
    case redCard = "red_card"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .kickoff: "Kickoff"
        case .goal: "Goals"
        case .halftime: "Half-time"
        case .fulltime: "Full-time result"
        case .yellowCard: "Yellow cards"
        case .redCard: "Red cards"
        }
    }
}

/// Wire map of event_type → enabled. Keys are passed through untouched (no
/// snake_case conversion) because they are already the backend's event names.
struct PreferencesBody: Codable, Sendable {
    var preferences: [String: Bool]
}

public enum APNsEnvironment: String, Codable, Sendable {
    case sandbox, production
}

struct APNsRegistration: Encodable, Sendable {
    var deviceToken: String
    var environment: APNsEnvironment
    var deviceLabel: String?
    var appVersion: String?
}

public struct APNsDevice: Decodable, Sendable, Equatable {
    public var id: String?
    public var environment: String?
    public var deviceLabel: String?
    public var appVersion: String?
}

public struct TestNotificationResult: Decodable, Sendable, Equatable {
    public var sent: Int
    public var failed: Int
}

extension APIClient {
    public func follows() async throws -> [FollowedTeam] {
        let response: FollowsResponse = try await get("/api/users/me/team-follows")
        return response.follows
    }

    public func follow(teamId: Int) async throws {
        let _: FollowResponse = try await send("POST", "/api/users/me/team-follows", body: FollowRequest(teamId: teamId))
    }

    public func unfollow(teamId: Int) async throws {
        try await sendIgnoringBody("DELETE", "/api/users/me/team-follows/\(teamId)")
    }

    public func notificationPreferences() async throws -> [NotificationEvent: Bool] {
        let body: PreferencesBody = try await getRawKeys("/api/users/me/notification-preferences")
        return Self.events(body.preferences)
    }

    @discardableResult
    public func setNotificationPreferences(_ preferences: [NotificationEvent: Bool]) async throws
        -> [NotificationEvent: Bool] {
        let wire = PreferencesBody(preferences: Dictionary(uniqueKeysWithValues: preferences.map { ($0.rawValue, $1) }))
        let body: PreferencesBody = try await sendRawKeys("PUT", "/api/users/me/notification-preferences", body: wire)
        return Self.events(body.preferences)
    }

    @discardableResult
    public func registerDevice(token: Data, environment: APNsEnvironment, label: String?,
                               appVersion: String?) async throws -> APNsDevice {
        try await send("POST", "/api/users/me/apns-devices", body: APNsRegistration(
            deviceToken: Self.hex(token), environment: environment, deviceLabel: label, appVersion: appVersion))
    }

    public func sendTestNotification() async throws -> TestNotificationResult {
        try await send("POST", "/api/users/me/notifications/test", body: [String: String]())
    }

    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }

    private static func events(_ wire: [String: Bool]) -> [NotificationEvent: Bool] {
        Dictionary(uniqueKeysWithValues: wire.compactMap { key, value in
            NotificationEvent(rawValue: key).map { ($0, value) }
        })
    }
}
