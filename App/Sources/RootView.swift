import SwiftUI
import MTKit

enum AppTab: String, CaseIterable, Hashable {
    case live, table, matches, club, profile
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            ProgressView().task { await app.bootstrap() }
        case .unreachable(let message):
            LaunchFailedView(message: message)
        case .signedOut:
            LoginView()
        case .signedIn:
            MainTabs()
        }
    }
}

/// Launch couldn't check the saved session. Without this the app sat on a spinner (SB-1285).
struct LaunchFailedView: View {
    @Environment(AppModel.self) private var app
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Can't reach Missing Table", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { app.retryLaunch() }
                .buttonStyle(.borderedProminent)
            Button("Sign Out", role: .destructive) { Task { await app.logout() } }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(PushManager.self) private var push
    @Environment(LeagueFilter.self) private var filter
    @Environment(MatchesFilterStore.self) private var matchesFilter
    @SceneStorage("tab") private var tab: AppTab = .table
    /// Matches being scored right now; the LIVE tab exists only while there are some (web App.vue).
    @State private var liveMatches: [LiveMatchSummary] = []
    static let livePoll: Duration = .seconds(30)

    var body: some View {
        TabView(selection: $tab) {
            if !liveMatches.isEmpty {
                Tab("LIVE", systemImage: "dot.radiowaves.left.and.right", value: AppTab.live) {
                    NavigationStack { LiveScreen(matches: liveMatches).withRoutes() }
                }
                .badge(liveMatches.count)
            }
            Tab("Table", systemImage: "list.number", value: AppTab.table) {
                NavigationStack { TableScreen().withRoutes() }
            }
            Tab("Matches", systemImage: "sportscourt", value: AppTab.matches) {
                NavigationStack { MatchesScreen().withRoutes() }
            }
            if app.role.seesClubTeams {
                Tab("My Club", systemImage: "shield.lefthalf.filled", value: AppTab.club) {
                    NavigationStack { ClubScreen().withRoutes() }
                }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack { ProfileScreen().withRoutes() }
            }
        }
        .task(id: app.profile?.id) { await startOnOwnTeam() }
        .sheet(isPresented: Binding(
            get: { push.pendingMatchId != nil },
            set: { if !$0 { push.pendingMatchId = nil } }
        )) {
            if let id = push.pendingMatchId { MatchByIdView(matchId: id) }
        }
        .onAppear {
            #if DEBUG
            // `-MTTab profile` on launch opens a tab (for simulator screenshots).
            if let raw = UserDefaults.standard.string(forKey: "MTTab"), let start = AppTab(rawValue: raw) { tab = start }
            #endif
        }
        .task {
            while !Task.isCancelled {
                liveMatches = (try? await app.client.liveMatches()) ?? liveMatches
                #if DEBUG
                // `-MTLiveMatch <id>` shows the LIVE tab for that match (simulator screenshots).
                let debugId = UserDefaults.standard.integer(forKey: "MTLiveMatch")
                if debugId > 0, liveMatches.isEmpty {
                    liveMatches = [LiveMatchSummary(matchId: debugId)]
                    tab = .live
                }
                #endif
                if liveMatches.isEmpty, tab == .live { tab = .table }
                try? await Task.sleep(for: Self.livePoll)
            }
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
            .navigationDestination(for: PlayerRoute.self) { PlayerView(player: $0) }
    }
}

extension MainTabs {
    /// First sign-in on this device: Table and Matches open on the user's team (age group,
    /// division, Flex bracket). Later choices are left alone.
    func startOnOwnTeam() async {
        guard let profile = app.profile, matchesFilter.needsHome(for: profile) else { return }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            if !matchesFilter.isLoaded { try await matchesFilter.load(using: app.client, leagues: filter.leagues) }
            try await matchesFilter.applyHome(for: profile, filter: filter, using: app.client)
        } catch {}
    }
}
