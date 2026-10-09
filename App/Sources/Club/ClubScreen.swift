import SwiftUI
import MTKit

/// My Club (web TeamRosterPage): the club's teams by age group, each opening the
/// team page with its roster and stats. Club fans (parents) see their club; admins
/// pick any club. Players and team managers land on their own team (starred), with
/// the club's other teams one back-swipe away.
struct ClubScreen: View {
    @Environment(AppModel.self) private var app
    @AppStorage("club.selectedId") private var pickedClubId: Int = 0
    @State private var clubs: [Club] = []
    @State private var teams: Loadable<[ClubTeam]> = .idle
    @State private var ownTeam: TeamRoute?
    @State private var openedOwnTeam = false

    private var ownClub: ClubRef? { app.profile?.displayClub }
    private var clubId: Int? { ownClub?.id ?? (pickedClubId == 0 ? nil : pickedClubId) }
    private var clubName: String {
        ownClub?.name ?? clubs.first { $0.id == clubId }?.name ?? "My Club"
    }
    private var ownTeamIds: [Int] { app.profile?.ownTeamIds ?? [] }

    var body: some View {
        Group {
            if clubId == nil {
                if app.role == .admin { clubPicker } else {
                    ContentUnavailableView("No Club", systemImage: "shield",
                                           description: Text("Your account isn't linked to a club yet."))
                }
            } else {
                LoadableView(state: teams, retry: load) { teams in
                    List {
                        ForEach(ClubTeam.byAgeGroup(teams), id: \.ageGroup) { group in
                            Section(group.ageGroup) {
                                ForEach(group.teams) { team in
                                    NavigationLink(value: route(team, ageGroup: group.ageGroup)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ownTeamIds.contains(team.id) ? "★ \(team.name)" : team.name)
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
        .navigationTitle(clubName)
        .toolbar {
            if app.role == .admin, ownClub == nil, clubId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Change Club") { pickedClubId = 0 }
                }
            }
        }
        .refreshable { await load() }
        .task(id: clubId) { await load() }
        .navigationDestination(item: $ownTeam) { TeamView(team: $0) }
        #if DEBUG
        // `-MTTeam <id>` opens that team on launch (simulator screenshots).
        .navigationDestination(isPresented: .constant(UserDefaults.standard.integer(forKey: "MTTeam") > 0)) {
            TeamView(team: TeamRoute(id: UserDefaults.standard.integer(forKey: "MTTeam"), name: "Team"))
        }
        #endif
    }

    private var clubPicker: some View {
        List(clubs) { club in
            Button {
                pickedClubId = club.id
            } label: {
                HStack(spacing: 12) {
                    ClubBadge(name: club.name, size: 28)
                    Text(club.name).foregroundStyle(.primary)
                }
            }
        }
        .overlay { if clubs.isEmpty { ProgressView() } }
    }

    /// Once per launch, so backing out to the club list keeps you there.
    private func openOwnTeam(in teams: [ClubTeam]) {
        guard !openedOwnTeam, app.profile != nil else { return }
        openedOwnTeam = true
        guard let team = ownTeamIds.lazy.compactMap({ id in teams.first { $0.id == id } }).first else { return }
        ownTeam = TeamRoute(id: team.id, name: team.name, ageGroup: app.profile?.ageGroup(forTeam: team.id))
    }

    /// Narrowed to the section's age group only for a squad that spans several.
    private func route(_ team: ClubTeam, ageGroup: String) -> TeamRoute {
        let ref = team.ageGroupNames.count > 1 ? team.ageGroups?.first { $0.name == ageGroup } : nil
        return TeamRoute(id: team.id, name: team.name, ageGroup: ref)
    }

    private func load() async {
        do {
            if clubs.isEmpty, app.role == .admin { clubs = try await app.client.clubs().sorted { $0.name < $1.name } }
            guard let clubId else { return }
            if teams.value == nil { teams = .loading }
            let loaded = try await app.client.clubTeams(clubId: clubId)
            teams = .loaded(loaded)
            openOwnTeam(in: loaded)
        } catch is CancellationError {
        } catch {
            app.handle(error)
            teams = .failed(error.displayMessage)
        }
    }
}
