import SwiftUI
import MTKit

/// A player's page (web PlayerDetailView): photo, number, positions, team and season
/// stats. Photos come from the player's account profile when the viewer is in the
/// same club; roster players without an account show their roster details only.
struct PlayerView: View {
    let player: PlayerRoute
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @State private var stats: Loadable<PlayerStatsResponse> = .idle
    @State private var account: PlayerAccountProfile?

    private var photo: String? {
        guard let account else { return player.photoUrl }
        switch account.profilePhotoSlot {
        case 2: return account.photo2Url ?? account.photos.first
        case 3: return account.photo3Url ?? account.photos.first
        default: return account.photo1Url ?? account.photos.first
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    PlayerAvatar(url: photo ?? player.photoUrl, name: player.name, size: 112)
                    Text(player.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    Text(player.teamName).font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section("Season Stats") {
                switch stats {
                case .loaded(let response):
                    let s = response.stats ?? SeasonStats()
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
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                case .idle, .loading:
                    ProgressView()
                }
            }
            if let photos = account?.photos, photos.count > 1 {
                Section("Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos, id: \.self) { url in
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
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var subtitle: String {
        let positions = account?.positions ?? player.positions
        return [player.jerseyNumber.map { "#\($0)" }, positions.isEmpty ? nil : positions.joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func load() async {
        if stats.value == nil { stats = .loading }
        do {
            if !filter.isLoaded { try await filter.load(using: app.client) }
            stats = .loaded(try await app.client.playerStats(playerId: player.playerId, seasonId: filter.seasonId))
            if let accountId = player.accountId {
                account = try? await app.client.playerAccountProfile(userId: accountId)
            }
        } catch is CancellationError {
        } catch {
            app.handle(error)
            stats = .failed(error.displayMessage)
        }
    }
}
