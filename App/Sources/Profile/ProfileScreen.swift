import SwiftUI
import MTKit

/// Profile tab, by role, as the web ProfileRouter: players get their card, season
/// stats and team record; fans (parents are club fans) get their club and follows;
/// managers get their teams. Everyone gets notifications and account controls.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @Environment(FollowStore.self) private var follows
    @State private var profile: Loadable<MyProfile> = .idle
    @State private var stats: PlayerStatsResponse?
    @State private var record: TeamRecord?

    var body: some View {
        LoadableView(state: profile, retry: load) { profile in
            List {
                Section {
                    ProfileHeader(profile: profile)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                switch profile.kind {
                case .player:
                    PlayerSections(profile: profile, stats: stats, record: record)
                case .clubFan, .teamFan:
                    FanSections(profile: profile)
                case .teamManager, .clubManager, .admin:
                    ManagerSections(profile: profile)
                }
                FollowingSection()
                AccountSections(profile: profile)
            }
        }
        .navigationTitle("Profile")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if profile.value == nil { profile = .loading }
        do {
            let loaded = try await app.client.profile()
            profile = .loaded(loaded)
            if !filter.isLoaded { try? await filter.load(using: app.client) }
            if !follows.isLoaded { try? await follows.load(using: app.client) }
            guard loaded.kind == .player else { return }
            let seasonId = loaded.currentTeams?.first?.season?.id ?? filter.seasonId
            stats = try? await app.client.myStats(seasonId: seasonId)
            if let teamId = loaded.currentTeams?.first?.teamId ?? loaded.teamId {
                let matches = (try? await app.client.matches(MatchQuery(seasonId: seasonId, teamId: teamId))) ?? []
                record = TeamRecord(teamId: teamId, matches: matches)
            }
        } catch is CancellationError {
        } catch {
            app.handle(error)
            profile = .failed(error.displayMessage)
        }
    }
}

// MARK: - Header

/// Player card in the profile's colours, like the web hero card.
private struct ProfileHeader: View {
    let profile: MyProfile

    private var background: Color { Color(hex: profile.primaryColor) ?? Color(hex: profile.displayClub?.primaryColor) ?? .accentColor }
    private var foreground: Color { Color(hex: profile.textColor) ?? .white }

    var body: some View {
        HStack(spacing: 16) {
            PlayerAvatar(url: profile.profilePhotoUrl, name: profile.fullName, size: 84)
                .overlay(Circle().stroke(foreground.opacity(0.6), lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.fullName).font(.title2.bold()).lineLimit(2)
                if profile.kind == .player {
                    Text(playerLine).font(.subheadline.weight(.semibold)).opacity(0.9)
                } else {
                    Text(profile.kind.title).font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                if let team = profile.currentTeams?.first {
                    Text(team.name).font(.subheadline)
                    if !team.subtitle.isEmpty { Text(team.subtitle).font(.caption).opacity(0.85) }
                } else if let club = profile.displayClub?.name {
                    Text(club).font(.subheadline)
                }
            }
            Spacer(minLength: 0)
            if let club = profile.displayClub {
                ClubLogo(url: club.logoUrl, name: club.name ?? "", size: 40)
            }
        }
        .foregroundStyle(foreground)
        .padding(16)
        .background(background.gradient, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var playerLine: String {
        let number = profile.playerNumber.map { "#\($0)" }
        let positions = profile.positions?.isEmpty == false ? profile.positions!.joined(separator: ", ") : nil
        return [number, positions].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Player

private struct PlayerSections: View {
    let profile: MyProfile
    let stats: PlayerStatsResponse?
    let record: TeamRecord?

    var body: some View {
        Section {
            if let s = stats?.stats {
                StatGrid(items: [
                    .init(label: "GP", value: "\(s.gamesPlayed)"),
                    .init(label: "GS", value: "\(s.gamesStarted)"),
                    .init(label: "MIN", value: "\(s.totalMinutes)"),
                    .init(label: "GOALS", value: "\(s.totalGoals)", highlight: true),
                    .init(label: "ASSISTS", value: "\(s.totalAssists)", highlight: true),
                    .init(label: "YC", value: "\(s.totalYellowCards)"),
                    .init(label: "RC", value: "\(s.totalRedCards)"),
                ])
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } else if stats?.linked == false {
                Text("Your account isn't linked to a roster spot yet. Ask your team manager to link you.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("No stats yet this season.").foregroundStyle(.secondary)
            }
        } header: {
            Text("My Stats")
        }

        if let record, record.played > 0 {
            Section("Team Season Record") {
                StatGrid(items: [
                    .init(label: "GAMES", value: "\(record.played)"),
                    .init(label: "W", value: "\(record.wins)"),
                    .init(label: "D", value: "\(record.draws)"),
                    .init(label: "L", value: "\(record.losses)"),
                    .init(label: "WIN %", value: "\(record.winPercentage)%", highlight: true),
                    .init(label: "GF", value: "\(record.goalsFor)"),
                    .init(label: "GA", value: "\(record.goalsAgainst)"),
                ])
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }

        TeamsSection(teams: profile.currentTeams ?? [], title: "My Team")

        if !profile.photos.isEmpty {
            Section("My Photos") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(profile.photos, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                            }
                            .frame(width: 110, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
    }
}

// MARK: - Fans and managers

private struct FanSections: View {
    let profile: MyProfile

    var body: some View {
        if let club = profile.displayClub, let name = club.name {
            Section("My Club") {
                HStack(spacing: 12) {
                    ClubLogo(url: club.logoUrl, name: name, size: 32)
                    Text(name).font(.headline)
                }
            }
        }
        TeamsSection(teams: profile.currentTeams ?? [], title: "My Team")
    }
}

private struct ManagerSections: View {
    let profile: MyProfile

    var body: some View {
        if let club = profile.displayClub, let name = club.name {
            Section(profile.kind == .admin ? "Club" : "My Club") {
                HStack(spacing: 12) {
                    ClubLogo(url: club.logoUrl, name: name, size: 32)
                    Text(name).font(.headline)
                }
            }
        }
        TeamsSection(teams: profile.currentTeams ?? [], title: "My Teams")
    }
}

/// Current team assignments, each opening the team page.
private struct TeamsSection: View {
    let teams: [CurrentTeam]
    let title: String

    var body: some View {
        if !teams.isEmpty {
            Section(title) {
                ForEach(teams, id: \.self) { team in
                    if let id = team.teamId {
                        NavigationLink(value: TeamRoute(id: id, name: team.name)) {
                            HStack(spacing: 12) {
                                ClubLogo(url: team.team?.club?.logoUrl, name: team.name, size: 28)
                                VStack(alignment: .leading) {
                                    Text(team.name)
                                    if !team.subtitle.isEmpty {
                                        Text(team.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Followed teams: what score-update notifications are sent for.
private struct FollowingSection: View {
    @Environment(AppModel.self) private var app
    @Environment(FollowStore.self) private var follows

    var body: some View {
        Section {
            if follows.teams.isEmpty {
                Text("Tap ☆ on a team page to follow it and get score updates.")
                    .foregroundStyle(.secondary)
            }
            ForEach(follows.teams) { team in
                NavigationLink(value: TeamRoute(id: team.teamId, name: team.name)) {
                    VStack(alignment: .leading) {
                        Text(team.name)
                        if !team.subtitle.isEmpty {
                            Text(team.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { follows.teams[$0] }
                Task {
                    for team in removed {
                        try? await follows.toggle(TeamRoute(id: team.teamId, name: team.name), using: app.client)
                    }
                }
            }
        } header: {
            Text("Following")
        }
    }
}

// MARK: - Account

private struct AccountSections: View {
    @Environment(AppModel.self) private var app
    @Environment(FollowStore.self) private var follows
    let profile: MyProfile

    var body: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell")
            }
        }
        Section("Account") {
            if let username = profile.username { LabeledContent("Username", value: username) }
            LabeledContent("Role", value: profile.kind.title)
            Button("Switch Account / Sign Out", role: .destructive) {
                Task {
                    await app.logout()
                    follows.reset()
                }
            }
        }
        #if DEBUG
        Section("Developer") {
            EnvironmentPicker()
            LabeledContent("API", value: app.environment.baseURL.absoluteString)
        }
        #endif
        Section {
            LabeledContent("Version", value: Bundle.main.appVersion)
        }
    }
}
