import SwiftUI
import MTKit

/// League-wide goal leaders for the selected season / age group / league / division
/// (/api/leaderboards/goals, as the Android leaderboard).
struct TopScorers: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[LeaderboardEntry]> = .idle

    private var selectionKey: [Int?] { [filter.seasonId, filter.ageGroupId, filter.leagueId, filter.divisionId] }

    var body: some View {
        LoadableView(state: state, retry: load) { rows in
            if rows.isEmpty {
                ContentUnavailableView("No Goals Yet", systemImage: "soccerball",
                                       description: Text("Top scorers appear once matches are scored live."))
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            HStack(spacing: 10) {
                                Text("\(row.rank ?? 0)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).lineLimit(1)
                                    Text(row.teamName ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.gamesPlayed.map(String.init) ?? "–")
                                    .foregroundStyle(.secondary).frame(width: 30)
                                Text("\(row.goals)").bold().frame(width: 30)
                            }
                            .font(.subheadline.monospacedDigit())
                        }
                    } header: {
                        HStack(spacing: 10) {
                            Text("#").frame(width: 24, alignment: .leading)
                            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                            Text("GP").frame(width: 30)
                            Text("G").frame(width: 30)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await load() }
        .task(id: selectionKey) { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            guard let seasonId = filter.seasonId else { state = .loaded([]); return }
            state = .loaded(try await app.client.goalLeaders(seasonId: seasonId, ageGroupId: filter.ageGroupId,
                                                              leagueId: filter.leagueId, divisionId: filter.divisionId))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}
