import Foundation
import Testing
@testable import MTKit

private let signedIn = AuthTokens(accessToken: "t", refreshToken: "r")

@Suite struct NotificationsTests {
    @Test func listsFollowsWithClubAndDivision() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (200, json("""
            {"follows": [{"team_id": 7, "created_at": "2026-10-01T00:00:00Z",
              "team": {"id": 7, "name": "Blues U14", "age_group_id": 3, "club": {"id": 1, "name": "Blues FC"},
                       "division": {"id": 4, "name": "Northeast", "leagues": {"id": 2, "name": "Homegrown"}}}}]}
            """))
        }
        let follows = try await client.follows()
        #expect(follows.map(\.teamId) == [7])
        #expect(follows[0].name == "Blues U14")
        #expect(follows[0].subtitle == "Blues FC · Northeast")
    }

    @Test func followPostsTeamIdAndUnfollowDeletes() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return request.httpMethod == "DELETE" ? (204, Data()) : (201, json(#"{"team_id": 7, "following": true}"#))
        }
        try await client.follow(teamId: 7)
        try await client.unfollow(teamId: 7)
        #expect(recorder.requests.map(\.httpMethod) == ["POST", "DELETE"])
        #expect(recorder.paths == ["/api/users/me/team-follows", "/api/users/me/team-follows/7"])
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: Int]
        #expect(body == ["team_id": 7])
    }

    @Test func preferencesKeepEventKeysAndDropUnknown() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (200, json(#"{"preferences": {"yellow_card": false, "goal": true, "future_event": true}}"#))
        }
        let prefs = try await client.notificationPreferences()
        #expect(prefs == [.yellowCard: false, .goal: true])

        try await client.setNotificationPreferences([.redCard: true])
        let sent = try JSONSerialization.jsonObject(with: recorder.requests[1].httpBody ?? Data()) as? [String: [String: Bool]]
        #expect(sent == ["preferences": ["red_card": true]])
        #expect(recorder.requests[1].httpMethod == "PUT")
    }

    @Test func registersDeviceTokenAsLowercaseHex() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (201, json(#"{"id": "d-1", "environment": "sandbox", "device_label": "iPhone"}"#))
        }
        let device = try await client.registerDevice(token: Data([0xAB, 0x01, 0xFF]), environment: .sandbox,
                                                     label: "iPhone", appVersion: "0.1.0")
        #expect(device.id == "d-1")
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: String]
        #expect(body == ["device_token": "ab01ff", "environment": "sandbox", "device_label": "iPhone",
                         "app_version": "0.1.0"])
    }

    @Test func eventTitlesCoverAllEvents() {
        #expect(NotificationEvent.allCases.map(\.rawValue)
            == ["kickoff", "goal", "halftime", "fulltime", "yellow_card", "red_card"])
    }
}
