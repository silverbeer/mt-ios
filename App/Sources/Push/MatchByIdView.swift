import SwiftUI
import MTKit

/// Opens a match from a notification tap: fetch by id, then show the detail.
struct MatchByIdView: View {
    let matchId: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var state: Loadable<Match> = .idle

    var body: some View {
        NavigationStack {
            LoadableView(state: state, retry: load) { match in
                MatchDetailView(match: match)
            }
            .withRoutes()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await app.client.match(id: matchId))
        } catch {
            app.handle(error)
            state = .failed(error.displayMessage)
        }
    }
}
