import SwiftUI
import MTKit

/// Live match (web LiveMatchView): scoreboard with running clock, the activity
/// stream (goals, cards, subs, status changes and chat, newest first) and a chat box.
/// Updates arrive via Supabase Realtime with a 15s poll as a fallback.
struct LiveMatchView: View {
    let matchId: Int
    @Environment(AppModel.self) private var app
    @State private var match: Match?
    @State private var live: LiveMatchState?
    @State private var events: [MatchEvent] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var failed: String?
    @State private var showingLineups = false

    static let fallbackPoll: Duration = .seconds(15)
    static let maxLength = 500

    private var canModerate: Bool { app.role.isManager }

    var body: some View {
        Group {
            if let match {
                List {
                    Section {
                        let timeline = MatchTimeline(events: events, homeTeamId: match.homeTeamId,
                                                     awayTeamId: match.awayTeamId)
                        VStack(spacing: 16) {
                            Scoreboard(match: match, status: live?.matchStatus ?? match.status,
                                       homeScore: live?.homeScore ?? match.homeScore,
                                       awayScore: live?.awayScore ?? match.awayScore, live: live)
                            if timeline.hasGoalsOrCards {
                                Divider()
                                TeamEventColumns(timeline: timeline)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section("Live") {
                        if events.isEmpty {
                            Text("No activity yet. Say hi 👋").foregroundStyle(.secondary)
                        }
                        ForEach(events) { event in
                            Group {
                                if event.kind == .message {
                                    ChatRow(event: event, isMine: event.createdBy == app.user?.id)
                                } else {
                                    TimelineRow(event: event, match: match)
                                }
                            }
                            .swipeActions {
                                if canModerate {
                                    Button("Delete", role: .destructive) { Task { await delete(event) } }
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { composer }
            } else if let failed {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(failed))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(match.map { "\($0.homeTeamName) v \($0.awayTeamName)" } ?? "Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if match != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLineups = true } label: {
                        Image(systemName: "person.3")
                    }
                    .accessibilityLabel("Lineups")
                }
            }
        }
        .sheet(isPresented: $showingLineups) {
            if let match { LiveLineupsSheet(match: match) }
        }
        .refreshable { await refresh() }
        .task(id: matchId) { await refresh() }
        .task(id: matchId) { await followRealtime() }
        .task(id: matchId) { await pollFallback() }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let sendError {
                Text(sendError).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField("Type a message…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft) { _, new in
                        if new.count > Self.maxLength { draft = String(new.prefix(Self.maxLength)) }
                    }
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill").font(.title2)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func followRealtime() async {
        for await _ in MatchRealtime.changes(matchId: matchId, config: app.environment.realtime) {
            await refresh()
        }
    }

    private func pollFallback() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.fallbackPoll)
            await refresh()
        }
    }

    private func refresh() async {
        do {
            async let state = app.client.liveState(matchId: matchId)
            async let latest = app.client.events(matchId: matchId)
            async let row = app.client.match(id: matchId)
            live = try await state
            events = try await latest  // newest first, as the web activity stream
            match = try await row
            failed = nil
        } catch is CancellationError {
        } catch {
            app.handle(error)
            if match == nil { failed = error.displayMessage }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            let posted = try await app.client.postMessage(matchId: matchId, text: text)
            draft = ""
            if !events.contains(where: { $0.id == posted.id }) { events.insert(posted, at: 0) }
        } catch {
            app.handle(error)
            sendError = error.displayMessage
        }
    }

    private func delete(_ event: MatchEvent) async {
        let before = events
        events.removeAll { $0.id == event.id }
        do {
            try await app.client.deleteEvent(matchId: matchId, eventId: event.id)
        } catch {
            events = before
            app.handle(error)
            sendError = error.displayMessage
        }
    }
}

/// A chat message: author, time, text. Your own messages are tinted.
private struct ChatRow: View {
    let event: MatchEvent
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.createdByUsername ?? "Anonymous").font(.caption.bold())
                Spacer()
                if let time = event.createdAt.flatMap(MTDate.timestamp) {
                    Text(time.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(event.message ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(isMine ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

/// Both lineups over the live view, fetched each time it opens so a lineup
/// set or changed after kickoff shows up.
private struct LiveLineupsSheet: View {
    let match: Match
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var home: Lineup?
    @State private var away: Lineup?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if loaded {
                    List { LineupSection(match: match, home: home, away: away) }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Lineups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                async let h = try? app.client.lineup(matchId: match.id, teamId: match.homeTeamId)
                async let a = try? app.client.lineup(matchId: match.id, teamId: match.awayTeamId)
                (home, away) = (await h ?? nil, await a ?? nil)
                loaded = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// LIVE tab: one live match opens straight away; several are listed (web App.vue).
struct LiveScreen: View {
    let matches: [LiveMatchSummary]

    var body: some View {
        if matches.count == 1, let only = matches.first {
            LiveMatchView(matchId: only.matchId)
        } else if matches.isEmpty {
            ContentUnavailableView("No Live Matches", systemImage: "dot.radiowaves.left.and.right",
                                   description: Text("Live matches show up here while they're being scored."))
                .navigationTitle("Live")
        } else {
            List(matches) { match in
                NavigationLink {
                    LiveMatchView(matchId: match.matchId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.homeTeamName ?? "Home")
                            Text(match.awayTeamName ?? "Away")
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(match.homeScore.map(String.init) ?? "–")
                            Text(match.awayScore.map(String.init) ?? "–")
                        }
                        .font(.body.monospacedDigit().bold())
                    }
                }
            }
            .navigationTitle("Live")
        }
    }
}
