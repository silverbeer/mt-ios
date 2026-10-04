import Foundation
import Testing
import MTKit
@testable import MissingTable

@Test func appTabsAreDefined() {
    #expect(AppTab.allCases.count == 3)
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
