import SwiftUI
import MTKit

@main
struct MissingTableApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @State private var filter = LeagueFilter()
    @State private var follows = FollowStore()
    @State private var matchesFilter = MatchesFilterStore()
    @State private var push = PushManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(filter)
                .environment(follows)
                .environment(matchesFilter)
                .environment(push)
                .onAppear {
                    delegate.push = push
                    push.attach(app)
                    #if DEBUG
                    // `-MTMatch <id>` opens a match as if from a notification (simulator screenshots).
                    let debugMatch = UserDefaults.standard.integer(forKey: "MTMatch")
                    if debugMatch > 0 { push.pendingMatchId = debugMatch }
                    #endif
                    follows.onFirstFollow = { [push] in
                        Task { await push.requestAuthorizationIfNeeded() }
                    }
                }
        }
    }
}
