import SwiftUI
import MTKit

struct TableScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[StandingRow]> = .idle

    /// Reload whenever any part of the selection changes.
    private var selectionKey: [Int?] { [filter.seasonId, filter.ageGroupId, filter.divisionId] }

    var body: some View {
        LoadableView(state: state, retry: load) { rows in
            if rows.isEmpty {
                ContentUnavailableView("No Standings", systemImage: "list.number",
                                       description: Text("No league results for \(filter.summary) yet."))
            } else {
                StandingsList(rows: rows)
            }
        }
        .navigationTitle(filter.division?.name ?? "Table")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { FilterButton() } }
        .refreshable { await load() }
        .task(id: selectionKey) { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            state = .loaded(try await app.client.table(seasonId: filter.seasonId, ageGroupId: filter.ageGroupId,
                                                         divisionId: filter.divisionId))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}

private struct StandingsList: View {
    let rows: [StandingRow]

    var body: some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if let teamId = row.teamId {
                        NavigationLink(value: TeamRoute(id: teamId, name: row.team)) {
                            StandingRowView(position: index + 1, row: row)
                        }
                    } else {
                        StandingRowView(position: index + 1, row: row)
                    }
                }
            } header: {
                StandingHeader()
            }
        }
        .listStyle(.plain)
    }
}

private enum Columns {
    static let position: CGFloat = 24
    static let stat: CGFloat = 26
    static let points: CGFloat = 32
}

private struct StandingHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("#").frame(width: Columns.position, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["P", "W", "D", "L", "GD"], id: \.self) { Text($0).frame(width: Columns.stat) }
            Text("Pts").frame(width: Columns.points)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct StandingRowView: View {
    let position: Int
    let row: StandingRow

    var body: some View {
        HStack(spacing: 4) {
            Text("\(position)")
                .frame(width: Columns.position, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.team).lineLimit(1)
                if let form = row.form, !form.isEmpty { FormStrip(results: form) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text("\(row.played)")
                Text("\(row.wins)")
                Text("\(row.draws)")
                Text("\(row.losses)")
                Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
            }
            .frame(width: Columns.stat)
            .foregroundStyle(.secondary)
            Text("\(row.points)").bold().frame(width: Columns.points)
        }
        .font(.subheadline.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position). \(row.team), \(row.points) points, played \(row.played), "
            + "won \(row.wins), drawn \(row.draws), lost \(row.losses)")
    }
}

/// Last-five results as coloured dots.
struct FormStrip: View {
    let results: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(results.suffix(5).enumerated()), id: \.offset) { _, result in
                Circle().fill(color(result)).frame(width: 6, height: 6)
            }
        }
    }

    private func color(_ result: String) -> Color {
        switch result {
        case "W": .green
        case "D": .gray
        case "L": .red
        default: .clear
        }
    }
}
