import Foundation
import SwiftUI
import Testing
import MTKit
@testable import MissingTable

@Test func appTabsAreDefined() {
    #expect(AppTab.allCases.count == 5)
}

@MainActor @Suite struct AppModelTests {
    private func defaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func bootstrapWithoutSessionGoesToSignIn() async {
        let app = AppModel(defaults: defaults(), makeTokens: { _ in InMemoryTokenStore() })
        await app.bootstrap()
        #expect(app.phase == .signedOut)
    }

    @Test func unauthorizedErrorSignsOut() async {
        let app = AppModel(defaults: defaults(), makeTokens: { _ in InMemoryTokenStore() })
        await app.bootstrap()
        app.handle(APIError.unauthorized)
        #expect(app.phase == .signedOut)
        #expect(app.user == nil)
    }

    /// SB-1285: a server that never answers ends in Retry / Sign Out, not an endless spinner.
    @Test func silentServerOffersRetryAndKeepsSession() async {
        let tokens = InMemoryTokenStore(AuthTokens(accessToken: "a", refreshToken: "r"))
        let app = AppModel(defaults: defaults(), makeTokens: { _ in tokens },
                           session: StubProtocol.session(.silent), launchLimit: .milliseconds(200))

        await app.bootstrap()

        guard case .unreachable = app.phase else {
            Issue.record("expected unreachable, got \(app.phase)")
            return
        }
        #expect(tokens.load() != nil)
        app.retryLaunch()
        #expect(app.phase == .launching)
        await app.logout()
        #expect(app.phase == .signedOut)
        #expect(tokens.load() == nil)
    }

    @Test func rejectedRefreshOnLaunchSignsOut() async {
        let tokens = InMemoryTokenStore(AuthTokens(accessToken: "a", refreshToken: "r"))
        let app = AppModel(defaults: defaults(), makeTokens: { _ in tokens },
                           session: StubProtocol.session(.rejecting))
        await app.bootstrap()
        #expect(app.phase == .signedOut)
        #expect(tokens.load() == nil)
    }

    @Test func environmentChoiceIsRemembered() async {
        let store = defaults()
        let app = AppModel(defaults: store, makeTokens: { _ in InMemoryTokenStore() })
        await app.switchEnvironment(.local)
        #expect(AppModel(defaults: store, makeTokens: { _ in InMemoryTokenStore() }).environment == .local)
    }

    /// SB-1309: a blocked author's chat disappears at once (their goals stay), and the list is
    /// dropped on sign-out.
    @Test func blockedAuthorsAreHiddenUntilSignOut() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let events = try decoder.decode([MatchEvent].self, from: Data("""
        [{"id": 1, "match_id": 1, "event_type": "message", "created_by": "u-1"},
         {"id": 2, "match_id": 1, "event_type": "message", "created_by": "u-9"},
         {"id": 3, "match_id": 1, "event_type": "message"},
         {"id": 4, "match_id": 1, "event_type": "goal", "created_by": "u-9"}]
        """.utf8))
        let app = AppModel(defaults: defaults(), makeTokens: { _ in InMemoryTokenStore() })
        #expect(app.visible(events).map(\.id) == [1, 2, 3, 4])

        app.noteBlocked("u-9")
        #expect(app.visible(events).map(\.id) == [1, 3, 4])

        await app.logout()
        #expect(app.blockedUserIds.isEmpty)
        #expect(app.visible(events).map(\.id) == [1, 2, 3, 4])
    }
}

@MainActor @Suite struct LeagueFilterTests {
    @Test func reconcileKeepsValidSelection() {
        var selection: Int? = 3
        LeagueFilter.reconcile(&selection, with: [1, 2, 3], fallback: 1)
        #expect(selection == 3)
    }

    @Test func reconcileFallsBackWhenSelectionVanished() {
        var selection: Int? = 9
        LeagueFilter.reconcile(&selection, with: [1, 2], fallback: 2)
        #expect(selection == 2)
    }

    @Test func selectionPersists() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let filter = LeagueFilter(defaults: defaults)
        filter.ageGroupId = 14
        #expect(LeagueFilter(defaults: defaults).ageGroupId == 14)
    }
}

@Suite struct PushPayloadTests {
    @Test func readsMatchIdFromBackendPayload() {
        #expect(PushManager.matchId(from: ["matchId": 42, "eventType": "goal"]) == 42)
        #expect(PushManager.matchId(from: ["matchId": "42"]) == 42)
        #expect(PushManager.matchId(from: ["aps": [:]]) == nil)
    }

    @Test func debugBuildsUseSandbox() {
        #expect(PushManager.apnsEnvironment == .sandbox)
    }
}

@MainActor @Suite struct MatchesFilterStoreTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test func selectionIsRememberedAcrossLaunches() {
        let store = defaults()
        let first = MatchesFilterStore(defaults: store)
        first.toggle(10)
        first.toggle(20)
        #expect(MatchesFilterStore(defaults: store).divisionIds == [10, 20])
    }

    @Test func leagueToggleSelectsThenClearsWholeLeague() {
        let store = MatchesFilterStore(defaults: defaults())
        let flex = MatchFilter.LeagueGroup(id: "league-2", title: "Flex", divisions: [
            Division(id: 20, name: "Empire", leagueId: 2), Division(id: 21, name: "New England", leagueId: 2)])
        store.toggle(10)
        store.toggleLeague(flex)
        #expect(store.divisionIds == [10, 20, 21])
        #expect(store.isWholeLeagueSelected(flex))
        store.toggleLeague(flex)
        #expect(store.divisionIds == [10])
    }

    @Test func emptySelectionMeansAll() {
        #expect(MatchesFilterStore(defaults: defaults()).summary == "All divisions")
    }
}

@Suite struct ColorHexTests {
    @Test func roundTripsHex() {
        #expect(Color(hex: "#1E40AF")?.hexString == "#1E40AF")
        #expect(Color(hex: "ff0000")?.hexString == "#FF0000")
        #expect(Color(hex: "nope") == nil)
    }
}

@MainActor @Suite struct HomeFilterOnceTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    private func profile(_ json: String) throws -> MyProfile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MyProfile.self, from: Data(json.utf8))
    }

    @Test func homeIsAppliedOncePerAccountAndRemembered() async throws {
        let store = defaults()
        let matches = MatchesFilterStore(defaults: store)
        let app = AppModel(defaults: store, makeTokens: { _ in InMemoryTokenStore() })
        let teamless = try profile(#"{"id": "u-1"}"#)
        #expect(matches.needsHome(for: teamless))
        #expect(!matches.needsHome(for: nil))

        // No team: nothing to apply, but the account is marked so it isn't retried.
        matches.divisionIds = [99]
        try await matches.applyHome(for: teamless, filter: LeagueFilter(defaults: store), using: app.client)
        #expect(matches.divisionIds == [99])
        #expect(!matches.needsHome(for: teamless))
        #expect(!MatchesFilterStore(defaults: store).needsHome(for: teamless))

        // A different account on the same device starts on its own team again.
        #expect(matches.needsHome(for: try profile(#"{"id": "u-2"}"#)))
    }
}


/// SB-1280: the built app declares its icon (an empty AppIcon set ships no CFBundleIcons entry).
@Test func appDeclaresItsIcon() {
    let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
    let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
    let name = primary?["CFBundleIconName"] as? String
    #expect(name == "AppIcon")
}

/// Network stand-ins for AppModel tests: `.silent` never answers, `.rejecting` answers 401
/// to everything (including the token refresh).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: String { case silent, rejecting }

    static func session(_ mode: Mode) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub": mode.rawValue]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.value(forHTTPHeaderField: "X-Stub") == Mode.rejecting.rawValue else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"detail": "rejected"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
