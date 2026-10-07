import Foundation
import Testing
@testable import MTKit

private let saved = AuthTokens(accessToken: "old-access", refreshToken: "old-refresh")
private let meBody = json("""
{"user": {"id": "u-1", "email": "fan@example.com",
          "profile": {"username": "fan", "display_name": "Fan One", "role": "team-fan", "club_id": 4}}}
""")

/// SB-1285: the launch check is bounded and ends in signed in, signed out or unreachable.
@Suite struct SessionCheckTests {
    @Test func noSavedSessionIsSignedOutWithoutNetwork() async {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore()) { request in
            recorder.record(request)
            return (200, meBody)
        }
        #expect(await client.checkSession() == .signedOut)
        #expect(recorder.requests.isEmpty)
    }

    @Test func oneMeRequestGivesUserAndProfile() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(saved)) { request in
            recorder.record(request)
            return (200, meBody)
        }

        guard case .signedIn(let user, let profile) = await client.checkSession() else {
            Issue.record("expected signed in")
            return
        }
        #expect(user.id == "u-1")
        #expect(user.label == "Fan One")
        #expect(profile?.id == "u-1")
        #expect(profile?.clubId == 4)
        #expect(recorder.paths == ["/api/auth/me"])
    }

    @Test func unreadableProfileStillSignsIn() async {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(saved)) { _ in
            (200, json(#"{"user": {"id": "u-1", "profile": {"positions": "not-a-list"}}}"#))
        }
        #expect(await client.checkSession() == .signedIn(User(id: "u-1"), nil))
    }

    @Test func silentServerTimesOutAndKeepsSession() async {
        let store = InMemoryTokenStore(saved)
        let client = StubURLProtocol.client(tokens: store) { _ in throw StubURLProtocol.NoAnswer() }

        let start = ContinuousClock.now
        let outcome = await client.checkSession(within: .milliseconds(200))

        guard case .unreachable(.transport) = outcome else {
            Issue.record("expected unreachable, got \(outcome)")
            return
        }
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(store.load() == saved)
    }

    @Test func stalledRefreshCountsAgainstTheSameLimit() async {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(saved)) { request in
            if request.url?.path == "/api/auth/refresh" { throw StubURLProtocol.NoAnswer() }
            return (401, json(#"{"detail": "expired"}"#))
        }
        let start = ContinuousClock.now
        guard case .unreachable(.transport) = await client.checkSession(within: .milliseconds(200)) else {
            Issue.record("expected unreachable")
            return
        }
        // The refresh is a shared task that cancellation doesn't reach; the check must not wait for it.
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func rejectedRefreshSignsOutAndClearsSession() async {
        let store = InMemoryTokenStore(saved)
        let client = StubURLProtocol.client(tokens: store) { request in
            (401, json(#"{"detail": "\#(request.url!.path) rejected"}"#))
        }
        #expect(await client.checkSession() == .signedOut)
        #expect(store.load() == nil)
    }

    @Test func serverErrorIsUnreachable() async {
        let store = InMemoryTokenStore(saved)
        let client = StubURLProtocol.client(tokens: store) { _ in (503, json(#"{"detail": "down"}"#)) }
        #expect(await client.checkSession() == .unreachable(.http(status: 503, detail: "down")))
        #expect(store.load() == saved)
    }
}
