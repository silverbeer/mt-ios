import Foundation
import Observation
import MTKit

/// App-wide session: which backend, who is signed in, and the client to talk to it.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        /// The saved session couldn't be checked (no answer in time, or server trouble).
        /// It is kept; the user picks Retry or Sign Out.
        case unreachable(String)
        case signedOut
        case signedIn(User)
    }

    private(set) var phase: Phase = .launching
    /// Full profile (role, club, teams); drives which tabs a user gets.
    private(set) var profile: MyProfile?
    /// Users the signed-in user has blocked. The server already hides their chat messages; this hides
    /// them the moment a block happens, before the next fetch. Their goals, cards and subs stay.
    private(set) var blockedUserIds: Set<String> = []
    private(set) var client: APIClient
    private(set) var environment: APIEnvironment
    private let defaults: UserDefaults
    private let makeTokens: @Sendable (APIEnvironment) -> TokenStore
    private let session: URLSession
    /// How long launch waits on the session check before offering Retry / Sign Out.
    private let launchLimit: Duration

    init(defaults: UserDefaults = .standard,
         makeTokens: @escaping @Sendable (APIEnvironment) -> TokenStore = {
             KeychainTokenStore(service: "io.silverbeer.mt.auth.\($0.rawValue)")
         },
         session: URLSession = .shared,
         launchLimit: Duration = .seconds(12)) {
        let environment = defaults.string(forKey: Keys.environment).flatMap { APIEnvironment(rawValue: $0) } ?? .production
        self.defaults = defaults
        self.makeTokens = makeTokens
        self.session = session
        self.launchLimit = launchLimit
        self.environment = environment
        self.client = APIClient(baseURL: environment.baseURL, session: session, tokens: makeTokens(environment))
    }

    var role: Role { profile?.kind ?? Role(raw: user?.role) }

    var user: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    /// Restore a saved session on launch, giving up after `launchLimit`.
    func bootstrap() async {
        switch await client.checkSession(within: launchLimit) {
        case .signedOut:
            phase = .signedOut
        case .signedIn(let user, let profile):
            self.profile = profile
            phase = .signedIn(user)
            Task { await loadBlocks() }
        case .unreachable(.transport):
            phase = .unreachable("No answer from the server. Check your connection and try again.")
        case .unreachable(let error):
            phase = .unreachable(error.displayMessage)
        }
    }

    /// From the unreachable screen: back to the launch spinner, which runs `bootstrap` again.
    func retryLaunch() {
        phase = .launching
    }

    func login(username: String, password: String) async throws {
        _ = try await client.login(username: username, password: password)
        let user = (try? await client.me()) ?? User(id: "", username: username)
        profile = try? await client.profile()
        phase = .signedIn(user)
        Task { await loadBlocks() }
    }

    func logout() async {
        await client.logout()
        profile = nil
        blockedUserIds = []
        phase = .signedOut
    }

    // MARK: Blocks

    /// Best effort: on failure the server-side filtering still applies.
    func loadBlocks() async {
        guard let blocks = try? await client.blocks() else { return }
        blockedUserIds = Set(blocks.map(\.userId))
    }

    /// Record a block made on the server (directly, or as a side effect of a report).
    func noteBlocked(_ userId: String) {
        blockedUserIds.insert(userId)
    }

    func block(userId: String) async throws {
        try await client.blockUser(id: userId)
        noteBlocked(userId)
    }

    func unblock(userId: String) async throws {
        try await client.unblockUser(id: userId)
        blockedUserIds.remove(userId)
    }

    /// `events` without chat messages from a blocked user.
    func visible(_ events: [MatchEvent]) -> [MatchEvent] {
        MatchEvent.visible(events, hiding: blockedUserIds)
    }

    /// Call from any screen's catch: a dead session sends the user back to sign-in.
    func handle(_ error: any Error) {
        if case APIError.unauthorized = error {
            profile = nil
            blockedUserIds = []
            phase = .signedOut
        }
    }

    func switchEnvironment(_ environment: APIEnvironment) async {
        guard environment != self.environment else { return }
        await client.logout()
        self.environment = environment
        defaults.set(environment.rawValue, forKey: Keys.environment)
        client = APIClient(baseURL: environment.baseURL, session: session, tokens: makeTokens(environment))
        blockedUserIds = []
        phase = .signedOut
    }

    private enum Keys {
        static let environment = "apiEnvironment"
    }
}

extension Error {
    /// Short message for an inline error state.
    var displayMessage: String {
        switch self as? APIError {
        case .unauthorized: "Please sign in again."
        case .http(let status, let detail): detail ?? "Server error (\(status))."
        case .decoding: "Unexpected response from the server."
        case .transport: "Can't reach Missing Table. Check your connection."
        case nil: localizedDescription
        }
    }
}
