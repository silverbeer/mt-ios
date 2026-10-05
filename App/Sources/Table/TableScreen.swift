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
                StandingsList(rows: rows, title: filter.division?.name)
            }
        }
        .navigationTitle(filter.ageGroup?.name ?? "Table")
        .navigationBarTitleDisplayMode(.inline)
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
    let title: String?

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
                VStack(alignment: .leading, spacing: 8) {
                    if let title {
                        Text(title).font(.headline).foregroundStyle(.primary).textCase(nil)
                    }
                    StandingHeader()
                }
            }
        }
        .listStyle(.plain)
    }
}

private enum Columns {
    static let position: CGFloat = 22
    static let stat: CGFloat = 30
    static let points: CGFloat = 34
}

/// Compact phone layout: # · Team · P · GD · Pts. W-D-L and form sit under the team name.
private struct StandingHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: Columns.position, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            Text("P").frame(width: Columns.stat)
            Text("GD").frame(width: Columns.stat)
            Text("Pts").frame(width: Columns.points)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct StandingRowView: View {
    let position: Int
    let row: StandingRow

    var body: some View {
        HStack(spacing: 6) {
            Text("\(position)")
                .frame(width: Columns.position, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.team)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text("\(row.wins)-\(row.draws)-\(row.losses)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let form = row.form, !form.isEmpty { FormStrip(results: form) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.played)")
                .frame(width: Columns.stat)
                .foregroundStyle(.secondary)
            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                .frame(width: Columns.stat)
                .foregroundStyle(.secondary)
            Text("\(row.points)")
                .bold()
                .frame(width: Columns.points)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position). \(row.team), \(row.points) points, played \(row.played), "
            + "won \(row.wins), drawn \(row.draws), lost \(row.losses), goal difference \(row.goalDifference)")
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
