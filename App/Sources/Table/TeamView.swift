import SwiftUI
import MTKit

struct TeamRoute: Hashable {
    let id: Int
    let name: String
}

/// A team's results and fixtures for the selected season.
struct TeamView: View {
    let team: TeamRoute
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @Environment(FollowStore.self) private var follows
    @State private var state: Loadable<MatchSchedule> = .idle
    @State private var followError: String?

    var body: some View {
        LoadableView(state: state, retry: load) { schedule in
            if schedule.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "sportscourt",
                                       description: Text("Nothing scheduled this season."))
            } else {
                ScheduleList(schedule: schedule)
            }
        }
        .navigationTitle(team.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let following = follows.isFollowing(team.id)
                Button {
                    Task {
                        do {
                            try await follows.toggle(team, using: app.client)
                        } catch {
                            app.handle(error)
                            followError = error.displayMessage
                        }
                    }
                } label: {
                    Label(following ? "Unfollow" : "Follow", systemImage: following ? "star.fill" : "star")
                }
                .sensoryFeedback(.selection, trigger: following)
            }
        }
        .alert("Couldn't update follow", isPresented: Binding(
            get: { followError != nil }, set: { if !$0 { followError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
        .refreshable { await load() }
        .task {
            if !follows.isLoaded { try? await follows.load(using: app.client) }
            await load()
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let matches = try await app.client.matches(MatchQuery(seasonId: filter.seasonId, teamId: team.id))
            state = .loaded(MatchSchedule(matches))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}

/// Live / fixtures / results sections; rows open the match.
struct ScheduleList: View {
    let schedule: MatchSchedule

    var body: some View {
        List {
            if !schedule.live.isEmpty {
                Section("Live") {
                    ForEach(schedule.live) { MatchLink(match: $0) }
                }
            }
            ForEach(schedule.fixtures) { day in
                Section(dayTitle(day.date)) {
                    ForEach(day.matches) { MatchLink(match: $0) }
                }
            }
            ForEach(schedule.results) { day in
                Section(dayTitle(day.date)) {
                    ForEach(day.matches) { MatchLink(match: $0) }
                }
            }
        }
    }
}

struct MatchLink: View {
    let match: Match

    var body: some View {
        NavigationLink(value: match) { MatchRowView(match: match) }
    }
}
