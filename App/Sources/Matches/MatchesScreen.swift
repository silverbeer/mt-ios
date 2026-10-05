import SwiftUI
import MTKit

/// One Monday–Sunday week of matches for the selected division, live matches pinned
/// on top. Week navigation matches the Android app and the web: ← · This Week · →,
/// always opening on the current week.
struct MatchesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @Environment(FollowStore.self) private var follows
    @State private var state: Loadable<[Match]> = .idle
    @AppStorage("matches.myTeamsOnly") private var myTeamsOnly = false

    @State private var weekOffset = 0
    @State private var loadedWeekOffset = 0
    static let liveRefresh: Duration = .seconds(30)

    private var week: MatchWeek { MatchWeek(containing: Date(), offset: weekOffset) }
    private var selectionKey: [Int?] { [filter.seasonId, filter.ageGroupId, filter.divisionId, weekOffset] }

    var body: some View {
        LoadableView(state: state, retry: load) { matches in
            let schedule = MatchSchedule.week(myTeamsOnly ? MatchSchedule.involving(follows.teamIds, in: matches) : matches)
            if schedule.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "sportscourt",
                                       description: Text("Nothing for \(filter.summary) this week."))
            } else {
                ScheduleList(schedule: schedule)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WeekNavigator(offset: $weekOffset, label: week.label)
        }
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !follows.teams.isEmpty {
                    Toggle(isOn: $myTeamsOnly) { Label("My Teams", systemImage: "star") }
                        .toggleStyle(.button)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { FilterButton() }
        }
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
        if state.value == nil || loadedWeekOffset != weekOffset { state = .loading }
        loadedWeekOffset = weekOffset
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            if !follows.isLoaded { try? await follows.load(using: app.client) }
            let week = self.week
            let matches = try await app.client.matches(MatchQuery(
                seasonId: filter.seasonId, ageGroupId: filter.ageGroupId, divisionId: filter.divisionId,
                startDate: week.startDay, endDate: week.endDay))
            // Server bounds are inclusive dates; keep the list strictly inside the week shown.
            state = .loaded(matches.filter { week.contains(day: $0.matchDate) })
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}

/// ← · This Week · → with the week's dates underneath.
struct WeekNavigator: View {
    @Binding var offset: Int
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    offset -= 1
                } label: {
                    Image(systemName: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Previous week")

                Button(offset == 0 ? "This Week" : "Back to this week") { offset = 0 }
                    .buttonStyle(.borderedProminent)
                    .disabled(offset == 0)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                Button {
                    offset += 1
                } label: {
                    Image(systemName: "chevron.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Next week")
            }
            .controlSize(.regular)
            Text(label)
                .font(.subheadline.bold())
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sensoryFeedback(.selection, trigger: offset)
    }
}
