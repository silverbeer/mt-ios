import SwiftUI
import MTKit

/// My Club (web TeamRosterPage): the club's teams by age group, each opening the
/// team page with its roster and stats. Club fans (parents) see their club; admins
/// pick any club.
struct ClubScreen: View {
    @Environment(AppModel.self) private var app
    @AppStorage("club.selectedId") private var pickedClubId: Int = 0
    @State private var clubs: [Club] = []
    @State private var teams: Loadable<[ClubTeam]> = .idle

    private var ownClub: ClubRef? { app.profile?.displayClub }
    private var clubId: Int? { ownClub?.id ?? (pickedClubId == 0 ? nil : pickedClubId) }
    private var clubName: String {
        ownClub?.name ?? clubs.first { $0.id == clubId }?.name ?? "My Club"
    }

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
                                    NavigationLink(value: TeamRoute(id: team.id, name: team.name)) {
                                        VStack(alignment: .leading, spacing: 2) {
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
                    ClubLogo(url: club.logoUrl, name: club.name, size: 28)
                    Text(club.name).foregroundStyle(.primary)
                }
            }
        }
        .overlay { if clubs.isEmpty { ProgressView() } }
    }

    private func load() async {
        do {
            if clubs.isEmpty, app.role == .admin { clubs = try await app.client.clubs().sorted { $0.name < $1.name } }
            guard let clubId else { return }
            if teams.value == nil { teams = .loading }
            teams = .loaded(try await app.client.clubTeams(clubId: clubId))
        } catch is CancellationError {
        } catch {
            app.handle(error)
            teams = .failed(error.displayMessage)
        }
    }
}
