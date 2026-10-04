import SwiftUI
import MTKit

/// One match. While live, polls the live state for score and events.
struct MatchDetailView: View {
    @Environment(AppModel.self) private var app
    @State private var match: Match
    @State private var live: LiveMatchState?

    static let livePoll: Duration = .seconds(15)

    init(match: Match) {
        _match = State(initialValue: match)
    }

    private var homeScore: Int? { live?.homeScore ?? match.homeScore }
    private var awayScore: Int? { live?.awayScore ?? match.awayScore }
    private var status: MatchStatus { live?.matchStatus ?? match.status }

    var body: some View {
        List {
            Section {
                Scoreboard(home: match.homeTeamName, away: match.awayTeamName,
                           homeScore: homeScore, awayScore: awayScore, status: status, match: match)
                    .listRowBackground(Color.clear)
            }
            Section("Details") {
                LabeledContent("Date", value: dayTitle(match.matchDate))
                LabeledContent("Kickoff", value: match.kickoffLabel)
                if let division = match.divisionName { LabeledContent("Division", value: division) }
                if let ageGroup = match.ageGroupName { LabeledContent("Age Group", value: ageGroup) }
                if let type = match.matchTypeName { LabeledContent("Competition", value: type) }
            }
            if let events = live?.recentEvents, !events.isEmpty {
                Section("Events") {
                    ForEach(events.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("\(match.homeTeamName) v \(match.awayTeamName)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await pollWhileLive() }
    }

    private func pollWhileLive() async {
        await refresh()
        while !Task.isCancelled, status == .live {
            try? await Task.sleep(for: Self.livePoll)
            await refresh()
        }
    }

    private func refresh() async {
        do {
            match = try await app.client.match(id: match.id)
            if match.status == .live || live != nil {
                live = try await app.client.liveState(matchId: match.id)
            }
        } catch is CancellationError {
        } catch {
            app.handle(error)
        }
    }
}

private struct Scoreboard: View {
    let home: String
    let away: String
    let homeScore: Int?
    let awayScore: Int?
    let status: MatchStatus
    let match: Match

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                Text(home).font(.headline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Group {
                    if let homeScore, let awayScore {
                        Text("\(homeScore) – \(awayScore)")
                    } else {
                        Text("v")
                    }
                }
                .font(.largeTitle.bold().monospacedDigit())
                .contentTransition(.numericText())
                Text(away).font(.headline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            MatchStatusBadge(match: { var m = match; m.matchStatus = status; return m }())
        }
        .padding(.vertical, 8)
        .animation(.default, value: homeScore)
        .animation(.default, value: awayScore)
    }
}

private struct EventRow: View {
    let event: MatchEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.minuteLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Image(systemName: event.symbol).foregroundStyle(event.tint)
            Text(event.message?.isEmpty == false ? event.message! : event.eventType.capitalized)
        }
    }
}

private extension MatchEvent {
    var minuteLabel: String {
        guard let minute = matchMinute else { return "" }
        if let extra = extraTime, extra > 0 { return "\(minute)+\(extra)'" }
        return "\(minute)'"
    }

    var symbol: String {
        switch eventType {
        case "goal": "soccerball"
        case "yellow_card", "red_card", "card": "rectangle.portrait.fill"
        case "substitution": "arrow.left.arrow.right"
        default: "circle.fill"
        }
    }

    var tint: Color {
        switch eventType {
        case "yellow_card": .yellow
        case "red_card": .red
        case "goal": .primary
        default: .secondary
        }
    }
}
