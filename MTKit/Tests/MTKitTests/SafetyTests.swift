import Foundation
import Testing
@testable import MTKit

private let signedIn = AuthTokens(accessToken: "t", refreshToken: "r")

@Suite struct SafetyTests {
    @Test func reportPostsReasonWithNullDetailsAndReturnsBlockedAuthor() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (201, json(#"{"reported": true, "blocked_user_id": "u-9"}"#))
        }
        let blocked = try await client.reportEvent(matchId: 4, eventId: 77, reason: .harassment)
        #expect(blocked == "u-9")
        #expect(recorder.requests.map(\.httpMethod) == ["POST"])
        #expect(recorder.paths == ["/api/matches/4/live/events/77/report"])
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: Any]
        #expect(body?["reason"] as? String == "harassment")
        #expect(body?.keys.contains("details") == true)
        #expect(body?["details"] is NSNull)
    }

    @Test func reportSendsDetailsWhenGiven() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (201, json(#"{"reported": true, "blocked_user_id": "u-9"}"#))
        }
        try await client.reportEvent(matchId: 4, eventId: 77, reason: .other, details: "rude")
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: String]
        #expect(body == ["reason": "other", "details": "rude"])
    }

    @Test func reportingOwnMessageSurfacesServerDetail() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (400, json(#"{"detail": "You can't report your own message"}"#))
        }
        await #expect(throws: APIError.http(status: 400, detail: "You can't report your own message")) {
            try await client.reportEvent(matchId: 4, eventId: 77, reason: .spam)
        }
    }

    @Test func blockPostsAndUnblockDeletes() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (204, Data())
        }
        try await client.blockUser(id: "u-9")
        try await client.unblockUser(id: "u-9")
        #expect(recorder.requests.map(\.httpMethod) == ["POST", "DELETE"])
        #expect(recorder.paths == ["/api/users/u-9/block", "/api/users/u-9/block"])
    }

    @Test func decodesBlocks() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (200, json("""
            [{"user_id": "u-9", "username": "loud", "created_at": "2026-10-09T12:00:00Z"},
             {"user_id": "u-8", "username": null, "created_at": "2026-10-08T12:00:00Z"}]
            """))
        }
        let blocks = try await client.blocks()
        #expect(recorder.paths == ["/api/users/me/blocks"])
        #expect(blocks.map(\.id) == ["u-9", "u-8"])
        #expect(blocks.map(\.displayName) == ["loud", "Unknown user"])
        #expect(blocks[0].createdAt == "2026-10-09T12:00:00Z")
    }

    @Test(arguments: [
        (422, ChatPostError.notAllowed, "That message contains language that isn't allowed."),
        (403, ChatPostError.banned, "You can no longer post in chat."),
        (429, ChatPostError.rateLimited, "You're sending messages too fast."),
    ])
    func refusedMessagesMapToChatErrors(status: Int, expected: ChatPostError, text: String) async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (status, json(#"{"detail": "server words"}"#))
        }
        do {
            _ = try await client.postMessage(matchId: 4, text: "hi")
            Issue.record("expected \(expected)")
        } catch let error as ChatPostError {
            #expect(error == expected)
            #expect(error.localizedDescription == text)
        }
    }

    @Test func otherPostFailuresStayAPIErrors() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (500, json(#"{"detail": "boom"}"#))
        }
        await #expect(throws: APIError.http(status: 500, detail: "boom")) {
            try await client.postMessage(matchId: 4, text: "hi")
        }
    }

    @Test func visibleHidesBlockedAuthorsChatOnly() {
        func event(_ id: Int, _ type: String = "message", by author: String?) -> MatchEvent {
            MatchEvent(id: id, matchId: 1, eventType: type, teamId: nil, playerName: nil, assistPlayerName: nil,
                       matchMinute: nil, extraTime: nil, message: "m", createdAt: nil, createdBy: author)
        }
        let events = [event(1, by: "u-1"), event(2, by: "u-9"), event(3, by: nil),
                      event(4, "goal", by: "u-9"), event(5, "yellow_card", by: "u-9")]
        // A blocked manager's goal and card stay; only their chat goes.
        #expect(MatchEvent.visible(events, hiding: ["u-9"]).map(\.id) == [1, 3, 4, 5])
        #expect(MatchEvent.visible(events, hiding: []).map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test func everyReasonHasATitle() {
        #expect(ReportReason.allCases.map(\.rawValue) == ["spam", "harassment", "hate", "sexual", "other"])
        #expect(ReportReason.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
