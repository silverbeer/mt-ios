import SwiftUI
import MTKit

enum AppTab: String, CaseIterable, Hashable {
    case table, matches, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            ProgressView().task { await app.bootstrap() }
        case .signedOut:
            LoginView()
        case .signedIn:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @Environment(PushManager.self) private var push
    @SceneStorage("tab") private var tab: AppTab = .table

    var body: some View {
        TabView(selection: $tab) {
            Tab("Table", systemImage: "list.number", value: AppTab.table) {
                NavigationStack { TableScreen().withRoutes() }
            }
            Tab("Matches", systemImage: "sportscourt", value: AppTab.matches) {
                NavigationStack { MatchesScreen().withRoutes() }
            }
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                NavigationStack { SettingsView().withRoutes() }
            }
        }
        .sheet(isPresented: Binding(
            get: { push.pendingMatchId != nil },
            set: { if !$0 { push.pendingMatchId = nil } }
        )) {
            if let id = push.pendingMatchId { MatchByIdView(matchId: id) }
        }
        .task {
            // Re-registers with APNs when permitted; the token callback uploads it.
            await push.refreshAuthorization()
            await push.uploadToken()
        }
    }
}

extension View {
    /// Navigation destinations shared by every tab's stack.
    func withRoutes() -> some View {
        navigationDestination(for: TeamRoute.self) { TeamView(team: $0) }
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
    }
}
