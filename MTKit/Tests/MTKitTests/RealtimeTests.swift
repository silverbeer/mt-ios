import Foundation
import Testing
@testable import MTKit

@Suite struct RealtimeTests {
    @Test func joinSubscribesToThisMatchsEventsAndRow() throws {
        let data = try MatchRealtime.joinMessage(matchId: 42, anonKey: "k", ref: "1")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["topic"] as? String == "realtime:match-42")
        #expect(object["event"] as? String == "phx_join")
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(payload["access_token"] as? String == "k")
        let config = try #require(payload["config"] as? [String: Any])
        let changes = try #require(config["postgres_changes"] as? [[String: String]])
        #expect(changes.map { $0["table"]! } == ["match_events", "matches"])
        #expect(changes.map { $0["filter"]! } == ["match_id=eq.42", "id=eq.42"])
    }

    @Test func classifiesServerMessages() {
        #expect(MatchRealtime.classify(json(#"{"event":"postgres_changes","topic":"t","payload":{"data":{}},"ref":null}"#)) == .change)
        #expect(MatchRealtime.classify(json(#"{"event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"1"}"#)) == .joined)
        #expect(MatchRealtime.classify(json(#"{"event":"phx_reply","payload":{"status":"ok"},"ref":"2"}"#)) == .other)
        #expect(MatchRealtime.classify(json(#"{"event":"phx_reply","payload":{"status":"error"},"ref":"1"}"#)) == .closed)
        #expect(MatchRealtime.classify(json(#"{"event":"phx_close","payload":{},"ref":"1"}"#)) == .closed)
        #expect(MatchRealtime.classify(json("not json")) == .other)
    }

    @Test func heartbeatTargetsPhoenixTopic() throws {
        let object = try JSONSerialization.jsonObject(with: MatchRealtime.heartbeatMessage(ref: "7")) as? [String: Any]
        #expect(object?["topic"] as? String == "phoenix")
        #expect(object?["event"] as? String == "heartbeat")
    }

    @Test func postMessageSendsTextAndIdempotencyKey() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(AuthTokens(accessToken: "t", refreshToken: "r"))) { request in
            recorder.record(request)
            return (200, json(#"{"id": 9, "match_id": 5, "event_type": "message", "message": "Go Blues!", "created_by_username": "tom"}"#))
        }
        let event = try await client.postMessage(matchId: 5, text: "Go Blues!", clientEventId: "c-1")
        #expect(event.createdByUsername == "tom")
        #expect(recorder.paths == ["/api/matches/5/live/message"])
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: String]
        #expect(body == ["message": "Go Blues!", "client_event_id": "c-1"])
    }
}
