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
    @State private var reporting: MatchEvent?
    @State private var blocking: MatchEvent?
    @State private var showingReported = false
    @State private var showingRules = false
    @AppStorage("chatRulesAccepted") private var rulesAccepted = false

    static let fallbackPoll: Duration = .seconds(15)
    static let maxLength = 500

    private var canModerate: Bool { app.role.isManager }

    private func isMine(_ event: MatchEvent) -> Bool {
        guard let author = event.createdBy else { return false }
        return author == app.user?.id
    }

    var body: some View {
        Group {
            if let match {
                content(match)
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
        .modifier(moderationDialogs)
        .refreshable { await refresh() }
        .task(id: matchId) { await refresh() }
        .task(id: matchId) { await followRealtime() }
        .task(id: matchId) { await pollFallback() }
    }

    // Split out of `body`: Xcode 26's type checker times out on the whole chain.
    private func content(_ match: Match) -> some View {
        let visible = app.visible(events)
        return List {
            Section {
                scoreSummary(match)
            }
            Section("Live") {
                if visible.isEmpty {
                    Text("No activity yet. Say hi 👋").foregroundStyle(.secondary)
                }
                ForEach(visible) { event in
                    row(event, match: match)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private func scoreSummary(_ match: Match) -> some View {
        let timeline = MatchTimeline(events: events, homeTeamId: match.homeTeamId,
                                     awayTeamId: match.awayTeamId)
        return VStack(spacing: 16) {
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

    @ViewBuilder
    private func eventView(_ event: MatchEvent, match: Match) -> some View {
        if event.kind == .message {
            ChatRow(event: event, isMine: isMine(event))
                .contextMenu { chatActions(for: event) }
        } else {
            TimelineRow(event: event, match: match)
        }
    }

    private func row(_ event: MatchEvent, match: Match) -> some View {
        let deletable = canModerate || (event.kind == .message && isMine(event))
        return eventView(event, match: match)
            .swipeActions {
                if deletable {
                    Button("Delete", role: .destructive) { Task { await delete(event) } }
                }
            }
    }

    private var moderationDialogs: ModerationDialogs {
        ModerationDialogs(reporting: $reporting, blocking: $blocking, showingReported: $showingReported,
                          report: { event, reason in await report(event, reason: reason) },
                          block: { event in await block(event) })
    }
}

/// Report / block confirmation dialogs and the "Report Sent" alert.
private struct ModerationDialogs: ViewModifier {
    @Binding var reporting: MatchEvent?
    @Binding var blocking: MatchEvent?
    @Binding var showingReported: Bool
    let report: (MatchEvent, ReportReason) async -> Void
    let block: (MatchEvent) async -> Void

    private func presence(_ binding: Binding<MatchEvent?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }

    func body(content: Content) -> some View {
        content
        .confirmationDialog("Report Message", isPresented: presence($reporting), titleVisibility: .visible,
                            presenting: reporting) { event in
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) { Task { await report(event, reason) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Why are you reporting this message?")
        }
        .confirmationDialog("Block \(blocking?.createdByUsername ?? "this user")?", isPresented: presence($blocking),
                            titleVisibility: .visible, presenting: blocking) { event in
            Button("Block", role: .destructive) { Task { await block(event) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see their messages anymore. You can unblock them in Profile.")
        }
        .alert("Report Sent", isPresented: $showingReported) {
            Button("OK") {}
        } message: {
            Text("Thanks — we review reports within 24 hours. You won't see messages from this user anymore.")
        }
    }
}

extension LiveMatchView {

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
        .sheet(isPresented: $showingRules) {
            ChatRulesSheet {
                rulesAccepted = true
                Task { await send() }
            }
        }
    }

    /// Long-press menu on a chat message: delete your own, report or block anyone else's.
    @ViewBuilder private func chatActions(for event: MatchEvent) -> some View {
        if isMine(event) {
            Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(event) } }
        } else {
            Button("Report Message…", systemImage: "exclamationmark.bubble") { reporting = event }
            if event.createdBy != nil {
                Button("Block \(event.createdByUsername ?? "User")", systemImage: "hand.raised", role: .destructive) {
                    blocking = event
                }
            }
        }
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
        guard rulesAccepted else {
            showingRules = true
            return
        }
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

    /// Reporting also blocks the author server-side.
    private func report(_ event: MatchEvent, reason: ReportReason) async {
        do {
            let author = try await app.client.reportEvent(matchId: matchId, eventId: event.id, reason: reason)
            hideMessages(from: author)
            showingReported = true
        } catch {
            app.handle(error)
            sendError = error.displayMessage
        }
    }

    private func block(_ event: MatchEvent) async {
        guard let author = event.createdBy else { return }
        do {
            try await app.block(userId: author)
            hideMessages(from: author)
        } catch {
            app.handle(error)
            sendError = error.displayMessage
        }
    }

    private func hideMessages(from author: String) {
        app.noteBlocked(author)
        events.removeAll { $0.isChat(byAnyOf: [author]) }
    }
}

/// Shown once, before the first message: the rules App Review (guideline 1.2) asks users to agree to.
private struct ChatRulesSheet: View {
    let agree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Be respectful. No harassment, hate, sexual content or spam. Objectionable content is removed and users who post it lose chat access.")
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Chat Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agree") {
                        dismiss()
                        agree()
                    }
                }
            }
        }
        .presentationDetents([.medium])
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
