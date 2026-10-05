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
                    // The link is a hidden background so the row gets no disclosure chevron,
                    // which would push the stat columns out of line with the header.
                    StandingRowView(position: index + 1, row: row)
                        .background {
                            if let teamId = row.teamId {
                                NavigationLink(value: TeamRoute(id: teamId, name: row.team)) { EmptyView() }
                                    .opacity(0)
                            }
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
    static let position: CGFloat = 26
    static let stat: CGFloat = 24
    static let points: CGFloat = 32
}

/// Phone layout: # · Team · GP · W · D · L · PTS. Header and rows share `Columns` widths.
private struct StandingHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("#").frame(width: Columns.position, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["GP", "W", "D", "L"], id: \.self) { Text($0).frame(width: Columns.stat) }
            Text("PTS").frame(width: Columns.points)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct StandingRowView: View {
    let position: Int
    let row: StandingRow
    /// Last-5 form only where there's room (iPad, landscape); never on a portrait phone.
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 4) {
            Text("\(position)")
                .frame(width: Columns.position, alignment: .leading)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(row.team)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if sizeClass == .regular, let form = row.form, !form.isEmpty { FormStrip(results: form) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                ForEach(Array([row.played, row.wins, row.draws, row.losses].enumerated()), id: \.offset) { _, value in
                    Text("\(value)")
                        .frame(width: Columns.stat)
                        .foregroundStyle(.secondary)
                }
                Text("\(row.points)")
                    .bold()
                    .frame(width: Columns.points)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .font(.subheadline.monospacedDigit())
        .contentShape(Rectangle())
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
