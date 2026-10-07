import SwiftUI
import MTKit

struct TeamRoute: Hashable {
    let id: Int
    let name: String
    /// Set when opened from one age group of a squad that spans several: matches and
    /// roster are narrowed to it.
    var ageGroup: NamedRef? = nil

    /// "IFA U15" when narrowed to an age group.
    var title: String { [name, ageGroup?.name].compactMap { $0 }.joined(separator: " ") }
}

/// A team for the selected season: matches, roster and player stats.
struct TeamView: View {
    let team: TeamRoute
    @Environment(AppModel.self) private var app
    @Environment(FollowStore.self) private var follows
    @State private var followError: String?
    @SceneStorage("team.section") private var section: Section = .matches

    enum Section: String, CaseIterable {
        case matches = "Matches", roster = "Roster", stats = "Stats"
    }

    var body: some View {
        Group {
            switch section {
            case .matches: TeamMatches(team: team)
            case .roster: TeamRoster(team: team)
            case .stats: TeamStats(team: team)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(team.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .task { if !follows.isLoaded { try? await follows.load(using: app.client) } }
        #if DEBUG
        .onAppear {
            // `-MTTeamSection roster` picks the segment on launch (simulator screenshots).
            if let raw = UserDefaults.standard.string(forKey: "MTTeamSection"), let start = Section(rawValue: raw.capitalized) {
                section = start
            }
        }
        #endif
    }
}

/// Results and fixtures for the season.
private struct TeamMatches: View {
    let team: TeamRoute
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<MatchSchedule> = .idle

    var body: some View {
        LoadableView(state: state, retry: load) { schedule in
            if schedule.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "sportscourt",
                                       description: Text("Nothing scheduled this season."))
            } else {
                ScheduleList(schedule: schedule)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            let matches = try await app.client.matches(MatchQuery(seasonId: filter.seasonId, ageGroupId: team.ageGroup?.id, teamId: team.id))
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

    /// Scroll to the latest result once per load, not on every refresh redraw.
    @State private var scrolledTo: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !schedule.live.isEmpty {
                    Section("Live") {
                        ForEach(schedule.live) { MatchLink(match: $0) }
                    }
                }
                ForEach(schedule.timeline) { day in
                    Section {
                        ForEach(day.matches) { MatchLink(match: $0) }
                    } header: {
                        // The scroll target is the date heading, so it lands in view too.
                        Text(dayTitle(day.date)).id(day.date)
                    }
                }
            }
            .onAppear { scrollToLatestResult(proxy) }
            .onChange(of: schedule.anchorDay) { scrollToLatestResult(proxy) }
        }
    }

    /// Season view: open on the latest result, upcoming below it, older results a scroll up.
    private func scrollToLatestResult(_ proxy: ScrollViewProxy) {
        guard schedule.live.isEmpty, let anchor = schedule.anchorDay, anchor != scrolledTo else { return }
        scrolledTo = anchor
        // A little below the top edge: flush .top tucks the date under the section picker.
        proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: 0.08))
    }
}

struct MatchLink: View {
    let match: Match

    var body: some View {
        NavigationLink(value: match) { MatchRowView(match: match) }
    }
}
