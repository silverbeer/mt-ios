import SwiftUI
import MTKit

/// One match: scoreboard, scorers and cards per team, the event timeline and match
/// details, consistent with the web MatchDetailView. Live matches tick a clock every
/// second and refresh score and events every 15s.
struct MatchDetailView: View {
    @Environment(AppModel.self) private var app
    @State private var match: Match
    @State private var live: LiveMatchState?
    @State private var events: [MatchEvent] = []

    static let livePoll: Duration = .seconds(15)

    init(match: Match) {
        _match = State(initialValue: match)
    }

    private var status: MatchStatus { live?.matchStatus ?? match.status }
    private var homeScore: Int? { live?.homeScore ?? match.homeScore }
    private var awayScore: Int? { live?.awayScore ?? match.awayScore }
    private var timeline: MatchTimeline {
        MatchTimeline(events: events, homeTeamId: match.homeTeamId, awayTeamId: match.awayTeamId)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Scoreboard(match: match, status: status, homeScore: homeScore, awayScore: awayScore, live: live)
                    if !timeline.homeGoals.isEmpty || !timeline.awayGoals.isEmpty
                        || !timeline.homeCards.isEmpty || !timeline.awayCards.isEmpty {
                        Divider()
                        TeamEventColumns(timeline: timeline)
                    }
                }
                .padding(.vertical, 8)
            }

            if !timeline.isEmpty {
                Section("Timeline") {
                    ForEach(timeline.all) { event in
                        TimelineRow(event: event, match: match)
                    }
                }
            }

            Section("Match Details") {
                LabeledContent("Date", value: dayTitle(match.matchDate))
                LabeledContent("Kickoff", value: match.kickoffLabel)
                if let type = match.matchTypeName { LabeledContent("Competition", value: type) }
                if let season = match.seasonName { LabeledContent("Season", value: season) }
                if let league = match.leagueName { LabeledContent("League", value: league) }
                if let division = match.divisionName { LabeledContent("Division", value: division) }
                if let ageGroup = match.ageGroupName { LabeledContent("Age Group", value: ageGroup) }
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
            // Events exist for matches scored live; the web fetches them for live and completed.
            if match.status == .live || match.status.isFinal || match.isLiveScored {
                events = (try? await app.client.events(matchId: match.id)) ?? events
            }
        } catch is CancellationError {
        } catch {
            app.handle(error)
        }
    }
}

// MARK: - Scoreboard

private struct Scoreboard: View {
    let match: Match
    let status: MatchStatus
    let homeScore: Int?
    let awayScore: Int?
    let live: LiveMatchState?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                TeamBadge(name: match.homeTeamName, logo: match.homeTeamClub?.logoUrl)
                VStack(spacing: 6) {
                    if let homeScore, let awayScore {
                        Text("\(homeScore) – \(awayScore)")
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText())
                    } else {
                        Text(match.kickoffLabel).font(.title2.bold())
                    }
                    if let home = match.homePenaltyScore, let away = match.awayPenaltyScore {
                        Text("(\(home)–\(away) pens)").font(.caption).foregroundStyle(.secondary)
                    }
                    StatusLine(status: status, live: live)
                }
                .frame(minWidth: 110)
                TeamBadge(name: match.awayTeamName, logo: match.awayTeamClub?.logoUrl)
            }
        }
        .animation(.default, value: homeScore)
        .animation(.default, value: awayScore)
    }
}

private struct TeamBadge: View {
    let name: String
    let logo: String?

    var body: some View {
        VStack(spacing: 8) {
            ClubLogo(url: logo, name: name, size: 56)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
    }
}

/// LIVE + ticking clock, HT, FT, or the plain status.
private struct StatusLine: View {
    let status: MatchStatus
    let live: LiveMatchState?

    var body: some View {
        if status == .live, let live {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let clock = LiveClock.read(live, now: context.date)
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                    Text(clock.display).font(.subheadline.monospacedDigit().bold())
                }
            }
        } else {
            switch status {
            case .completed: Text("Full Time").font(.caption.bold()).foregroundStyle(.secondary)
            case .forfeit: Text("Forfeit").font(.caption.bold()).foregroundStyle(.secondary)
            case .postponed: Text("Postponed").font(.caption.bold()).foregroundStyle(.orange)
            case .cancelled: Text("Cancelled").font(.caption.bold()).foregroundStyle(.secondary)
            case .live: Text("LIVE").font(.caption.bold()).foregroundStyle(.red)
            case .scheduled, .tbd, .unknown: EmptyView()
            }
        }
    }
}

// MARK: - Scorers and cards

/// Home events on the left, away on the right, as under the web scoreboard.
private struct TeamEventColumns: View {
    let timeline: MatchTimeline

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            column(goals: timeline.homeGoals, cards: timeline.homeCards, alignment: .leading)
            column(goals: timeline.awayGoals, cards: timeline.awayCards, alignment: .trailing)
        }
        .font(.footnote)
    }

    private func column(goals: [MatchEvent], cards: [MatchEvent], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            ForEach(goals) { goal in
                Label {
                    Text("\(goal.playerName ?? "Goal") \(goal.minuteLabel)")
                } icon: {
                    Image(systemName: "soccerball")
                }
            }
            ForEach(cards) { card in
                Label {
                    Text("\(card.playerName ?? "Card") \(card.minuteLabel)")
                } icon: {
                    CardIcon(red: card.kind == .redCard)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct CardIcon: View {
    let red: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(red ? Color.red : Color.yellow)
            .frame(width: 9, height: 13)
    }
}

// MARK: - Timeline

private struct TimelineRow: View {
    let event: MatchEvent
    let match: Match

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.minuteLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var teamName: String? {
        switch event.teamId {
        case match.homeTeamId: match.homeTeamName
        case match.awayTeamId: match.awayTeamName
        default: nil
        }
    }

    @ViewBuilder private var icon: some View {
        switch event.kind {
        case .goal: Image(systemName: "soccerball")
        case .yellowCard: CardIcon(red: false)
        case .redCard: CardIcon(red: true)
        case .substitution: Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
        case .statusChange: Image(systemName: "flag.fill").foregroundStyle(.secondary)
        case .message, .other: Image(systemName: "text.bubble").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        let message = event.message?.isEmpty == false ? event.message : nil
        switch event.kind {
        case .goal: return "Goal — \(event.playerName ?? teamName ?? "")"
        case .yellowCard: return "Yellow card — \(event.playerName ?? teamName ?? "")"
        case .redCard: return "Red card — \(event.playerName ?? teamName ?? "")"
        case .substitution, .statusChange, .message, .other:
            return message ?? event.eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var detail: String? {
        switch event.kind {
        case .goal:
            let parts = [teamName, event.assistPlayerName.map { "Assist: \($0)" }].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .yellowCard, .redCard:
            return event.playerName == nil ? nil : teamName
        default:
            return nil
        }
    }
}
