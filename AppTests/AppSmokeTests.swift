import Testing
@testable import MissingTable

@Test func appTabsAreDefined() {
    #expect(AppTab.allCases.count == 3)
}
