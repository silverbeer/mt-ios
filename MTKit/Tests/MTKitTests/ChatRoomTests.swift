import Foundation
import Testing
@testable import MTKit

private let signedIn = AuthTokens(accessToken: "t", refreshToken: "r")

/// Club chat rooms (backend SB-1330): each club playing has its own room.
@Suite struct ChatRoomTests {
    @Test(arguments: [
        ("Live chat is open to members of the clubs playing", ChatPostError.notAMember,
         "Live chat is open to members of the clubs playing."),
        ("Chat has closed for this match", ChatPostError.closed, "Chat has closed for this match."),
        ("You can no longer post in chat", ChatPostError.banned, "You can no longer post in chat."),
    ])
    func a403IsWordedByItsDetail(detail: String, expected: ChatPostError, text: String) async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (403, json(#"{"detail": "\#(detail)"}"#))
        }
        do {
            _ = try await client.postMessage(matchId: 4, text: "hi")
            Issue.record("expected \(expected)")
        } catch let error as ChatPostError {
            #expect(error == expected)
            #expect(error.localizedDescription == text)
        }
    }

    @Test func liveStateDecodesTheViewersRoom() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (200, json(#"""
            {"match_id": 4, "chat": {"available": true, "club_id": 10,
              "rooms": [{"club_id": 10, "name": "IFA"}, {"club_id": 20, "name": "NEFC"}], "closed": false}}
            """#))
        }
        let state = try await client.liveState(matchId: 4)
        #expect(state.chat == ChatAccess(available: true, clubId: 10,
                                         rooms: [ChatRoom(clubId: 10, name: "IFA"), ChatRoom(clubId: 20, name: "NEFC")]))
        #expect(state.chat?.canPost == true)
    }

    @Test func aServerWithoutRoomsLeavesChatNil() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (200, json(#"{"match_id": 4}"#))
        }
        #expect(try await client.liveState(matchId: 4).chat == nil)
    }

    @Test func closedChatCannotPost() {
        #expect(!ChatAccess(available: true, clubId: 10, closed: true).canPost)
        #expect(!ChatAccess(available: false).canPost)
    }

    @Test func aChosenRoomIsSentOnReadsAndPosts() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            if request.httpMethod == "POST" {
                return (200, json(#"{"id": 1, "match_id": 4, "event_type": "message"}"#))
            }
            return (200, json(request.url?.path.hasSuffix("/events") == true ? "[]" : #"{"match_id": 4}"#))
        }
        _ = try await client.liveState(matchId: 4, chatClubId: 20)
        _ = try await client.events(matchId: 4, chatClubId: 20)
        _ = try await client.postMessage(matchId: 4, text: "hi", clubId: 20)

        let queries = recorder.requests.prefix(2).map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        #expect(queries[0].contains(URLQueryItem(name: "chat_club_id", value: "20")))
        #expect(queries[1].contains(URLQueryItem(name: "chat_club_id", value: "20")))
        let body = try JSONSerialization.jsonObject(with: recorder.requests[2].httpBody ?? Data()) as? [String: Any]
        #expect(body?["club_id"] as? Int == 20)
    }

    @Test func noRoomSendsNoRoomParameters() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (200, json(#"{"id": 1, "match_id": 4, "event_type": "message"}"#))
        }
        _ = try await client.postMessage(matchId: 4, text: "hi")
        let body = try JSONSerialization.jsonObject(with: recorder.requests[0].httpBody ?? Data()) as? [String: Any]
        #expect(body?.keys.contains("club_id") == false)
    }
}
