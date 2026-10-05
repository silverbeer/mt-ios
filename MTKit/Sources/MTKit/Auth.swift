import Foundation
import Security

public struct AuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Int?

    public init(accessToken: String, refreshToken: String, expiresAt: Int? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Where the client keeps its session between launches.
public protocol TokenStore: Sendable {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens?)
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?

    public init(_ tokens: AuthTokens? = nil) { self.tokens = tokens }

    public func load() -> AuthTokens? { lock.withLock { tokens } }
    public func save(_ tokens: AuthTokens?) { lock.withLock { self.tokens = tokens } }
}

/// Keychain-backed store: one generic-password item holding the JSON-encoded tokens.
///
/// The session is also kept in memory, so a keychain failure (e.g. an unsigned
/// simulator build gets errSecMissingEntitlement, -34018) only loses the session
/// across launches instead of signing the user out on the very next request.
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account = "session"
    private let lock = NSLock()
    private var cached: AuthTokens?
    private var hasCache = false

    public init(service: String = "io.silverbeer.mt.auth") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> AuthTokens? {
        lock.withLock {
            if hasCache { return cached }
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            cached = try? JSONDecoder().decode(AuthTokens.self, from: data)
            hasCache = true
            return cached
        }
    }

    public func save(_ tokens: AuthTokens?) {
        lock.withLock {
            cached = tokens
            hasCache = true
            SecItemDelete(query as CFDictionary)
            guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}

// MARK: - Wire shapes

struct LoginRequest: Encodable, Sendable {
    var username: String
    var password: String
}

/// `POST /api/auth/login` — flat.
struct LoginResponse: Decodable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int?
    var user: User
}

struct RefreshRequest: Encodable, Sendable {
    var refreshToken: String
}

/// `POST /api/auth/refresh` — nested under `session`.
struct RefreshResponse: Decodable, Sendable {
    struct Session: Decodable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Int?
    }
    var session: Session
}

/// `GET /api/auth/me` — profile fields live under `user.profile`.
struct MeResponse: Decodable, Sendable {
    struct MeUser: Decodable, Sendable {
        struct Profile: Decodable, Sendable {
            var username: String?
            var displayName: String?
            var role: String?
            var teamId: Int?
            var clubId: Int?
        }
        var id: String
        var email: String?
        var profile: Profile?
    }
    var user: MeUser

    var asUser: User {
        User(id: user.id, username: user.profile?.username, email: user.email,
             displayName: user.profile?.displayName, role: user.profile?.role,
             teamId: user.profile?.teamId, clubId: user.profile?.clubId)
    }
}
