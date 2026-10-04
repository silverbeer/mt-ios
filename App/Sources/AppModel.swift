import Foundation
import Observation
import MTKit

/// App-wide session: which backend, who is signed in, and the client to talk to it.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn(User)
    }

    private(set) var phase: Phase = .launching
    private(set) var client: APIClient
    private(set) var environment: APIEnvironment
    private let defaults: UserDefaults
    private let makeTokens: @Sendable (APIEnvironment) -> TokenStore

    init(defaults: UserDefaults = .standard,
         makeTokens: @escaping @Sendable (APIEnvironment) -> TokenStore = {
             KeychainTokenStore(service: "io.silverbeer.mt.auth.\($0.rawValue)")
         }) {
        let environment = defaults.string(forKey: Keys.environment).flatMap { APIEnvironment(rawValue: $0) } ?? .production
        self.defaults = defaults
        self.makeTokens = makeTokens
        self.environment = environment
        self.client = APIClient(baseURL: environment.baseURL, tokens: makeTokens(environment))
    }

    var user: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    /// Restore a saved session on launch.
    func bootstrap() async {
        guard await client.isSignedIn else {
            phase = .signedOut
            return
        }
        do {
            phase = .signedIn(try await client.me())
        } catch APIError.unauthorized {
            phase = .signedOut
        } catch {
            // Offline or server trouble: keep the session, show a placeholder user.
            phase = .signedIn(User(id: "", displayName: "Offline"))
        }
    }

    func login(username: String, password: String) async throws {
        _ = try await client.login(username: username, password: password)
        let user = (try? await client.me()) ?? User(id: "", username: username)
        phase = .signedIn(user)
    }

    func logout() async {
        await client.logout()
        phase = .signedOut
    }

    /// Call from any screen's catch: a dead session sends the user back to sign-in.
    func handle(_ error: any Error) {
        if case APIError.unauthorized = error { phase = .signedOut }
    }

    func switchEnvironment(_ environment: APIEnvironment) async {
        guard environment != self.environment else { return }
        await client.logout()
        self.environment = environment
        defaults.set(environment.rawValue, forKey: Keys.environment)
        client = APIClient(baseURL: environment.baseURL, tokens: makeTokens(environment))
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
