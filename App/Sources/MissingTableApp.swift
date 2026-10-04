import SwiftUI
import MTKit

@main
struct MissingTableApp: App {
    @State private var app = AppModel()
    @State private var filter = LeagueFilter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(filter)
        }
    }
}
