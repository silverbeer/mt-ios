import SwiftUI
import MTKit

/// Profile → Blocked Users: everyone whose chat you've hidden, with Unblock.
struct BlockedUsersView: View {
    @Environment(AppModel.self) private var app
    @State private var blocks: Loadable<[BlockedUser]> = .idle
    @State private var error: String?

    var body: some View {
        LoadableView(state: blocks, retry: load) { blocked in
            if blocked.isEmpty {
                ContentUnavailableView("No Blocked Users", systemImage: "hand.raised",
                                       description: Text("People you block or report in live chat show up here."))
            } else {
                List {
                    Section {
                        ForEach(blocked) { user in
                            HStack {
                                Text(user.displayName)
                                Spacer()
                                Button("Unblock") { Task { await unblock(user) } }
                                    .buttonStyle(.borderless)
                            }
                            .swipeActions {
                                Button("Unblock", role: .destructive) { Task { await unblock(user) } }
                            }
                        }
                    } footer: {
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if blocks.value == nil { blocks = .loading }
        do {
            blocks = .loaded(try await app.client.blocks())
        } catch is CancellationError {
        } catch {
            app.handle(error)
            if blocks.value == nil { blocks = .failed(error.displayMessage) }
        }
    }

    private func unblock(_ user: BlockedUser) async {
        error = nil
        do {
            try await app.unblock(userId: user.userId)
            if let current = blocks.value { blocks = .loaded(current.filter { $0.id != user.id }) }
        } catch {
            app.handle(error)
            self.error = error.displayMessage
        }
    }
}
