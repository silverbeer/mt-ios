import Foundation
import Testing
import MTKit
@testable import MissingTable

@Test func appTabsAreDefined() {
    #expect(AppTab.allCases.count == 4)
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

    @Test func environmentChoiceIsRemembered() async {
        let store = defaults()
        let app = AppModel(defaults: store, makeTokens: { _ in InMemoryTokenStore() })
        await app.switchEnvironment(.local)
        #expect(AppModel(defaults: store, makeTokens: { _ in InMemoryTokenStore() }).environment == .local)
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
