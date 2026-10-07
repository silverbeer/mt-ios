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
    }

    func logout() async {
        await client.logout()
        profile = nil
        phase = .signedOut
    }

    /// Call from any screen's catch: a dead session sends the user back to sign-in.
    func handle(_ error: any Error) {
        if case APIError.unauthorized = error {
            profile = nil
            phase = .signedOut
        }
    }

    func switchEnvironment(_ environment: APIEnvironment) async {
        guard environment != self.environment else { return }
        await client.logout()
        self.environment = environment
        defaults.set(environment.rawValue, forKey: Keys.environment)
        client = APIClient(baseURL: environment.baseURL, session: session, tokens: makeTokens(environment))
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
