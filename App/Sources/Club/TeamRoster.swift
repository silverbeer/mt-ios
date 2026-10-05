import SwiftUI
import MTKit

/// Opens a player's page. Carries what the roster already knows so the page can
/// render before its own requests finish.
struct PlayerRoute: Hashable {
    let playerId: Int
    let name: String
    let jerseyNumber: Int?
    let positions: [String]
    let photoUrl: String?
    let accountId: String?
    let teamName: String

    init(_ player: RosterPlayer, teamName: String) {
        playerId = player.id
        name = player.name
        jerseyNumber = player.jerseyNumber
        positions = player.positions ?? []
        photoUrl = player.photoUrl
        accountId = player.userProfile?.id
        self.teamName = teamName
    }

    init(_ row: TeamPlayerStats, teamName: String) {
        playerId = row.playerId
        name = row.name
        jerseyNumber = row.jerseyNumber
        positions = []
        photoUrl = nil
        accountId = nil
        self.teamName = teamName
    }
}

/// Team roster by jersey number, with photos for players who have an account.
struct TeamRoster: View {
    let team: TeamRoute
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[RosterPlayer]> = .idle

    var body: some View {
        LoadableView(state: state, retry: load) { roster in
            if roster.isEmpty {
                ContentUnavailableView("No Roster", systemImage: "person.3",
                                       description: Text("No players listed for this season."))
            } else {
                List(roster) { player in
                    NavigationLink(value: PlayerRoute(player, teamName: team.name)) {
                        HStack(spacing: 12) {
                            Text(player.jerseyNumber.map(String.init) ?? "–")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            PlayerAvatar(url: player.photoUrl, name: player.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                if let positions = player.positions, !positions.isEmpty {
                                    Text(positions.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            guard let seasonId = filter.seasonId else { state = .loaded([]); return }
            let roster = try await app.client.roster(teamId: team.id, seasonId: seasonId)
            state = .loaded(roster.sorted { ($0.jerseyNumber ?? 999, $0.name) < ($1.jerseyNumber ?? 999, $1.name) })
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}

/// Season stats for every player: GP GS G A YC RC, sorted by goals as the API returns.
struct TeamStats: View {
    let team: TeamRoute
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[TeamPlayerStats]> = .idle

    private static let columns = ["GP", "GS", "G", "A", "YC", "RC"]
    private static let stat: CGFloat = 26

    var body: some View {
        LoadableView(state: state, retry: load) { rows in
            if rows.isEmpty {
                ContentUnavailableView("No Stats Yet", systemImage: "chart.bar",
                                       description: Text("Stats appear once matches are scored live."))
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            NavigationLink(value: PlayerRoute(row, teamName: team.name)) {
                                HStack(spacing: 4) {
                                    Text(row.jerseyNumber.map(String.init) ?? "")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .leading)
                                    Text(row.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    ForEach(Array(values(row).enumerated()), id: \.offset) { index, value in
                                        Text("\(value)")
                                            .fontWeight(index == 2 ? .bold : .regular)
                                            .foregroundStyle(index == 2 ? .primary : .secondary)
                                            .frame(width: Self.stat)
                                    }
                                }
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Text("#").frame(width: 24, alignment: .leading)
                            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(Self.columns, id: \.self) { Text($0).frame(width: Self.stat) }
                        }
                        .font(.caption.weight(.semibold))
                        // Keep header columns over the row columns despite the row chevron.
                        .padding(.trailing, 18)
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func values(_ row: TeamPlayerStats) -> [Int] {
        [row.gamesPlayed, row.gamesStarted, row.totalGoals, row.totalAssists, row.totalYellowCards, row.totalRedCards]
            .map { $0 ?? 0 }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            state = .loaded(try await app.client.teamStats(teamId: team.id, seasonId: filter.seasonId))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}
