import Foundation
import Testing
@testable import MTKit

private let signedIn = AuthTokens(accessToken: "old-access", refreshToken: "old-refresh")

@Suite struct APIClientTests {
    @Test func loginStoresTokensAndReturnsUser() async throws {
        let recorder = Recorder()
        let store = InMemoryTokenStore()
        let client = StubURLProtocol.client(tokens: store) { request in
            recorder.record(request)
            return (200, json("""
            {"access_token": "a1", "refresh_token": "r1", "expires_at": 1800000000, "expires_in": 3600,
             "user": {"id": "u-1", "username": "fan", "display_name": "Fan One", "role": "fan"}}
            """))
        }

        let user = try await client.login(username: "fan", password: "pw")

        #expect(user.label == "Fan One")
        #expect(store.load() == AuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: 1800000000))
        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/auth/login")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["username": "fan", "password": "pw"])
    }

    @Test func loginWithBadPasswordThrowsUnauthorized() async {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore()) { _ in
            (401, json(#"{"detail": "Invalid credentials"}"#))
        }
        await #expect(throws: APIError.unauthorized) { try await client.login(username: "x", password: "y") }
    }

    @Test func requestWithoutSessionThrowsUnauthorizedWithoutNetwork() async {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore()) { request in
            recorder.record(request)
            return (200, json("[]"))
        }
        await #expect(throws: APIError.unauthorized) { try await client.seasons() }
        #expect(recorder.requests.isEmpty)
    }

    @Test func tableSendsBearerAndQuery() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (200, json(#"{"standings": [{"team": "Blues", "team_id": 7, "points": 3}]}"#))
        }

        let rows = try await client.table(seasonId: 3, ageGroupId: 2, divisionId: nil)

        #expect(rows.map(\.team) == ["Blues"])
        let request = try #require(recorder.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
        #expect(request.url?.query == "age_group_id=2&match_type=League&season_id=3")
    }

    @Test func expiredAccessTokenRefreshesOnceAndRetries() async throws {
        let recorder = Recorder()
        let store = InMemoryTokenStore(signedIn)
        let client = StubURLProtocol.client(tokens: store) { request in
            recorder.record(request)
            switch (request.url!.path, request.value(forHTTPHeaderField: "Authorization")) {
            case ("/api/auth/refresh", _):
                return (200, json("""
                {"success": true, "session": {"access_token": "new-access", "refresh_token": "new-refresh",
                 "expires_at": 1, "token_type": "bearer"}}
                """))
            case (_, "Bearer new-access"):
                return (200, json(#"[{"id": 1, "name": "2026-27", "is_current": true}]"#))
            default:
                return (401, json(#"{"detail": "expired"}"#))
            }
        }

        let seasons = try await client.seasons()

        #expect(seasons.first?.isCurrent == true)
        #expect(recorder.paths == ["/api/seasons", "/api/auth/refresh", "/api/seasons"])
        #expect(store.load()?.refreshToken == "new-refresh")
        let refreshBody = try JSONSerialization.jsonObject(with: recorder.requests[1].httpBody ?? Data())
        #expect((refreshBody as? [String: String]) == ["refresh_token": "old-refresh"])
    }

    @Test func rejectedRefreshClearsSession() async {
        let store = InMemoryTokenStore(signedIn)
        let client = StubURLProtocol.client(tokens: store) { _ in
            (401, json(#"{"detail": "nope"}"#))
        }

        await #expect(throws: APIError.unauthorized) { try await client.ageGroups() }
        #expect(store.load() == nil)
    }

    @Test func serverErrorSurfacesDetail() async {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (503, json(#"{"detail": "Database unavailable"}"#))
        }

        await #expect(throws: APIError.http(status: 503, detail: "Database unavailable")) {
            try await client.match(id: 1)
        }
    }

    @Test func matchQueryOmitsNilParameters() async throws {
        let recorder = Recorder()
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { request in
            recorder.record(request)
            return (200, json("[]"))
        }

        _ = try await client.matches(MatchQuery(divisionId: 4, startDate: "2026-10-01"))

        #expect(recorder.requests.first?.url?.query == "division_id=4&start_date=2026-10-01")
    }

    @Test func meFlattensProfile() async throws {
        let client = StubURLProtocol.client(tokens: InMemoryTokenStore(signedIn)) { _ in
            (200, json("""
            {"success": true, "user": {"id": "u-9", "email": "a@b.c",
             "profile": {"username": "coach", "display_name": "Coach K", "role": "club_manager", "club_id": 4}}}
            """))
        }

        let user = try await client.me()

        #expect(user == User(id: "u-9", username: "coach", email: "a@b.c", displayName: "Coach K",
                             role: "club_manager", clubId: 4))
    }

    @Test func logoutClearsTokens() async {
        let store = InMemoryTokenStore(signedIn)
        let client = StubURLProtocol.client(tokens: store) { _ in (200, Data()) }
        await client.logout()
        #expect(store.load() == nil)
        #expect(await client.isSignedIn == false)
    }
}
