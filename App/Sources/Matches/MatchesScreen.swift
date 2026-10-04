import SwiftUI
import MTKit

/// Results and fixtures for the selected division, live matches pinned on top.
struct MatchesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[Match]> = .idle

    /// Window around today: recent results and the next few weeks of fixtures.
    static let daysBack = 14
    static let daysAhead = 28
    static let liveRefresh: Duration = .seconds(30)

    private var selectionKey: [Int?] { [filter.seasonId, filter.ageGroupId, filter.divisionId] }

    var body: some View {
        LoadableView(state: state, retry: load) { matches in
            let schedule = MatchSchedule(matches)
            if schedule.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "sportscourt",
                                       description: Text("Nothing for \(filter.summary) in the next few weeks."))
            } else {
                ScheduleList(schedule: schedule)
            }
        }
        .navigationTitle("Matches")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { FilterButton() } }
        .refreshable { await load() }
        .task(id: selectionKey) {
            await load()
            // Keep live scores fresh while this screen is visible.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liveRefresh)
                if state.value?.contains(where: { $0.status == .live }) == true { await load() }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            let today = Date()
            let start = Calendar.current.date(byAdding: .day, value: -Self.daysBack, to: today) ?? today
            let end = Calendar.current.date(byAdding: .day, value: Self.daysAhead, to: today) ?? today
            state = .loaded(try await app.client.matches(MatchQuery(
                seasonId: filter.seasonId, ageGroupId: filter.ageGroupId, divisionId: filter.divisionId,
                startDate: MTDate.dayString(start), endDate: MTDate.dayString(end))))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}
