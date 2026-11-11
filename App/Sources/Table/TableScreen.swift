import SwiftUI
import MTKit

struct TableScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var state: Loadable<[StandingRow]> = .idle

    #if DEBUG
    @State private var debugTeam: TeamRoute?
    #endif

    /// The selection, carried onto a team's matches when a row is opened.
    private var scope: MatchScope? {
        MatchScope.make(ageGroup: filter.ageGroup.map { NamedRef(id: $0.id, name: $0.name) },
                        division: filter.division.map { NamedRef(id: $0.id, name: $0.name) })
    }

    /// Reload whenever any part of the selection changes.
    private var selectionKey: [Int?] { [filter.seasonId, filter.ageGroupId, filter.divisionId] }

    var body: some View {
        standings
        .navigationTitle(filter.ageGroup?.name ?? "Table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { FilterButton() } }
    }

    private var standings: some View {
        LoadableView(state: state, retry: load) { rows in
            if rows.isEmpty {
                ContentUnavailableView("No Standings", systemImage: "list.number",
                                       description: Text("No league results for \(filter.summary) yet."))
            } else {
                StandingsList(rows: rows, title: filter.division?.name, scope: scope)
            }
        }
        .refreshable { await load() }
        .task(id: selectionKey) { await load() }
        #if DEBUG
        // `-MTTableTeam "IFA"` opens that row's team as a tap would (simulator screenshots).
        .navigationDestination(item: $debugTeam) { TeamView(team: $0) }
        .onChange(of: state.value) { _, rows in
            guard debugTeam == nil, let name = UserDefaults.standard.string(forKey: "MTTableTeam"),
                  let row = rows?.first(where: { $0.team == name }), let id = row.teamId else { return }
            debugTeam = TeamRoute(id: id, name: row.team, matchScope: scope)
        }
        #endif
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

/// The standings as a table: `#` and Team pinned on the left, every stat column (header
/// included) scrolling sideways together. Rows arrive in official rank order (points per match
/// for MLS NEXT), so position is always `index + 1` and nothing here re-sorts.
private struct StandingsList: View {
    let rows: [StandingRow]
    let title: String?
    /// The Table's age group and division, carried onto each team's matches.
    let scope: MatchScope?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var compactTeamWidth: CGFloat = 132
    /// Horizontal scroll of the stat rows, mirrored onto the pinned header's stat labels.
    @State private var statsOffset: CGFloat = 0

    private var teamWidth: CGFloat { sizeClass == .regular ? compactTeamWidth * 1.7 : compactTeamWidth }
    /// Last-5 form only where there's room (iPad, landscape), as the last scrolling column.
    private var columns: [StandingsColumn] { StandingsColumn.columns(showForm: sizeClass == .regular) }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                link(row) {
                                    PinnedCell(position: index + 1, row: row, teamWidth: teamWidth)
                                        .frame(height: rowHeight)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(StandingsAccessibility.label(position: index + 1, row: row))
                                .accessibilityAddTraits(row.teamId == nil ? [] : .isButton)
                                .overlay(alignment: .bottom) { Divider() }
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(rows) { row in
                                    link(row) {
                                        StatCells(row: row, columns: columns).frame(height: rowHeight)
                                    }
                                    .overlay(alignment: .bottom) { Divider() }
                                }
                            }
                        }
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x + $0.contentInsets.leading } action: { _, x in
                            statsOffset = x
                        }
                        // VoiceOver reads each row whole from its pinned cell.
                        .accessibilityHidden(true)
                    }
                } header: {
                    header
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline)
                    .padding(.horizontal, StatLayout.edge)
            }
            HStack(spacing: 0) {
                HStack(spacing: StatLayout.spacing) {
                    Text("#").frame(width: StatLayout.position, alignment: .leading)
                    Text("Team").frame(width: teamWidth, alignment: .leading)
                }
                .padding(.leading, StatLayout.edge)
                .padding(.trailing, StatLayout.spacing)
                // Not a ScrollView: it follows the rows' scroll offset, so header and cells stay aligned.
                StatHeader(columns: columns)
                    .fixedSize()
                    .offset(x: -statsOffset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func link(_ row: StandingRow, @ViewBuilder label: () -> some View) -> some View {
        if let teamId = row.teamId {
            NavigationLink(value: TeamRoute(id: teamId, name: row.team, matchScope: scope), label: label)
                .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

private enum StatLayout {
    static let edge: CGFloat = 16
    static let spacing: CGFloat = 6
    static let position: CGFloat = 26
}

/// One scrolling column of the Table. Header and cells share `width`, so they stay in line.
private struct StandingsColumn: Identifiable, Sendable {
    let id: String
    let width: CGFloat
    /// PPM is the ranking column.
    var emphasized = false
    var primary = false
    let value: @Sendable (StandingRow) -> String

    /// Same order as web: GP, Pts and PPM first so a phone shows why a team ranks where it does.
    static let stats: [StandingsColumn] = [
        StandingsColumn(id: "GP", width: 26) { "\($0.played)" },
        StandingsColumn(id: "Pts", width: 32, primary: true) { "\($0.points)" },
        StandingsColumn(id: "PPM", width: 42, emphasized: true, primary: true) { StandingsFormat.rate($0.pointsPerMatch) },
        StandingsColumn(id: "W", width: 26) { "\($0.wins)" },
        StandingsColumn(id: "D", width: 26) { "\($0.draws)" },
        StandingsColumn(id: "L", width: 26) { "\($0.losses)" },
        StandingsColumn(id: "GF", width: 28) { "\($0.goalsFor)" },
        StandingsColumn(id: "GA", width: 28) { "\($0.goalsAgainst)" },
        StandingsColumn(id: "GD", width: 34) { StandingsFormat.goalDifference($0.goalDifference) },
        StandingsColumn(id: "GD/M", width: 48) { StandingsFormat.rate($0.gdPerMatch, signed: true) },
        StandingsColumn(id: "GF/M", width: 44) { StandingsFormat.rate($0.gfPerMatch) },
        StandingsColumn(id: "GA/M", width: 44) { StandingsFormat.rate($0.gaPerMatch) },
    ]

    static let form = StandingsColumn(id: "Form", width: 48) { _ in "" }

    static func columns(showForm: Bool) -> [StandingsColumn] { showForm ? stats + [form] : stats }
}

private struct StatHeader: View {
    let columns: [StandingsColumn]

    var body: some View {
        HStack(spacing: StatLayout.spacing) {
            ForEach(columns) { column in
                Text(column.id)
                    .frame(width: column.width, alignment: column.id == StandingsColumn.form.id ? .leading : .trailing)
                    .foregroundStyle(column.emphasized ? .primary : .secondary)
            }
        }
        .padding(.trailing, StatLayout.edge)
    }
}

/// `#`, badge and team name: the part of a row that never scrolls sideways.
private struct PinnedCell: View {
    let position: Int
    let row: StandingRow
    let teamWidth: CGFloat

    var body: some View {
        HStack(spacing: StatLayout.spacing) {
            Text("\(position)")
                .frame(width: StatLayout.position, alignment: .leading)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ClubBadge(name: row.team)
                Text(row.team)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: teamWidth, alignment: .leading)
        }
        .padding(.leading, StatLayout.edge)
        .padding(.trailing, StatLayout.spacing)
        .frame(maxHeight: .infinity)
        .font(.subheadline.monospacedDigit())
        .contentShape(Rectangle())
    }
}

/// A row's stat values, laid out to the same `StandingsColumn` widths as the header.
private struct StatCells: View {
    let row: StandingRow
    let columns: [StandingsColumn]

    var body: some View {
        HStack(spacing: StatLayout.spacing) {
            ForEach(columns) { column in
                Group {
                    if column.id == StandingsColumn.form.id {
                        if let form = row.form, !form.isEmpty { FormStrip(results: form) }
                    } else {
                        Text(column.value(row))
                            .fontWeight(column.emphasized ? .semibold : nil)
                            .foregroundStyle(column.primary ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: column.width, alignment: column.id == StandingsColumn.form.id ? .leading : .trailing)
            }
        }
        .padding(.trailing, StatLayout.edge)
        .frame(maxHeight: .infinity)
        .font(.subheadline.monospacedDigit())
        .contentShape(Rectangle())
    }
}

enum StandingsAccessibility {
    /// One spoken row: rank, team, then the stats that decide it.
    static func label(position: Int, row: StandingRow) -> String {
        let ppm = row.pointsPerMatch.map { "\(StandingsFormat.rate($0)) points per match" } ?? "points per match unavailable"
        return "\(position). \(row.team), \(row.points) points, \(ppm), played \(row.played), "
            + "won \(row.wins), drawn \(row.draws), lost \(row.losses), "
            + "goal difference \(StandingsFormat.goalDifference(row.goalDifference))"
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
