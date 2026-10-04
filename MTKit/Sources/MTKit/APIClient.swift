import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// No session, or the refresh token was rejected. The user must sign in.
    case unauthorized
    case http(status: Int, detail: String?)
    case decoding(String)
    case transport(String)
}

extension JSONDecoder {
    static var mt: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension JSONEncoder {
    static var mt: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

public enum APIEnvironment: String, CaseIterable, Sendable {
    case production, local

    public var baseURL: URL {
        switch self {
        case .production: URL(string: "https://api.missingtable.com")!
        case .local: URL(string: "http://localhost:8000")!
        }
    }
}

/// Async client for the Missing Table backend.
///
/// Attaches the bearer token to every request except login/refresh. On a 401 it
/// refreshes once (concurrent 401s share one refresh) and retries; if the refresh
/// itself is rejected the session is cleared and `APIError.unauthorized` is thrown.
public actor APIClient {
    public let baseURL: URL
    private let session: URLSession
    private let tokens: TokenStore
    private var refreshTask: Task<AuthTokens, any Error>?

    public init(baseURL: URL, session: URLSession = .shared, tokens: TokenStore) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
    }

    public var isSignedIn: Bool { tokens.load() != nil }

    // MARK: Auth

    @discardableResult
    public func login(username: String, password: String) async throws -> User {
        let body = try JSONEncoder.mt.encode(LoginRequest(username: username, password: password))
        let request = makeRequest("POST", "/api/auth/login", body: body)
        let (data, response) = try await perform(request)
        guard response.statusCode != 401 else { throw APIError.unauthorized }
        let login: LoginResponse = try decode(data, response)
        tokens.save(AuthTokens(accessToken: login.accessToken, refreshToken: login.refreshToken,
                               expiresAt: login.expiresAt))
        return login.user
    }

    public func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens.save(nil)
    }

    public func me() async throws -> User {
        let me: MeResponse = try await get("/api/auth/me")
        return me.asUser
    }

    // MARK: Reference data

    public func seasons() async throws -> [Season] { try await get("/api/seasons") }
    public func currentSeason() async throws -> Season { try await get("/api/current-season") }
    public func ageGroups() async throws -> [AgeGroup] { try await get("/api/age-groups") }
    public func leagues() async throws -> [League] { try await get("/api/leagues") }

    public func divisions(leagueId: Int? = nil) async throws -> [Division] {
        try await get("/api/divisions", query: ["league_id": leagueId.map(String.init)])
    }

    // MARK: Table + matches

    public func table(seasonId: Int?, ageGroupId: Int?, divisionId: Int?,
                      matchType: String = "League") async throws -> [StandingRow] {
        let response: TableResponse = try await get("/api/table", query: [
            "season_id": seasonId.map(String.init),
            "age_group_id": ageGroupId.map(String.init),
            "division_id": divisionId.map(String.init),
            "match_type": matchType,
        ])
        return response.standings
    }

    public func matches(_ query: MatchQuery) async throws -> [Match] {
        try await get("/api/matches", query: query.items)
    }

    public func match(id: Int) async throws -> Match { try await get("/api/matches/\(id)") }

    public func liveMatches() async throws -> [LiveMatchSummary] { try await get("/api/matches/live") }

    public func liveState(matchId: Int) async throws -> LiveMatchState {
        try await get("/api/matches/\(matchId)/live")
    }

    // MARK: Plumbing

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send(makeRequest("GET", path, query: query))
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: some Encodable) async throws -> T {
        try await send(makeRequest(method, path, body: try JSONEncoder.mt.encode(body)))
    }

    /// For endpoints whose response body is ignored (e.g. DELETE → 204).
    func sendIgnoringBody(_ method: String, _ path: String) async throws {
        _ = try await authorized(makeRequest(method, path))
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await authorized(request)
        return try decode(data, response)
    }

    private func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let current = tokens.load() else { throw APIError.unauthorized }
        let first = try await perform(request, bearer: current.accessToken)
        guard first.1.statusCode == 401 else { return try checked(first) }
        let renewed = try await refreshed(after: current)
        return try checked(try await perform(request, bearer: renewed.accessToken))
    }

    /// One refresh at a time; a caller whose token was already replaced reuses the new one.
    private func refreshed(after stale: AuthTokens) async throws -> AuthTokens {
        if let latest = tokens.load(), latest.accessToken != stale.accessToken { return latest }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refresh(using: stale.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func refresh(using refreshToken: String) async throws -> AuthTokens {
        let body = try JSONEncoder.mt.encode(RefreshRequest(refreshToken: refreshToken))
        let (data, response) = try await perform(makeRequest("POST", "/api/auth/refresh", body: body))
        if response.statusCode == 401 {
            tokens.save(nil)
            throw APIError.unauthorized
        }
        let renewed: RefreshResponse = try decode(data, response)
        let next = AuthTokens(accessToken: renewed.session.accessToken,
                              refreshToken: renewed.session.refreshToken,
                              expiresAt: renewed.session.expiresAt)
        tokens.save(next)
        return next
    }

    private func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:],
                             body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        if !items.isEmpty { components.queryItems = items }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest, bearer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("not HTTP") }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func checked(_ result: (Data, HTTPURLResponse)) throws -> (Data, HTTPURLResponse) {
        let (data, response) = result
        if response.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, detail: Self.detail(from: data))
        }
        return result
    }

    private func decode<T: Decodable>(_ data: Data, _ response: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(status: response.statusCode, detail: Self.detail(from: data))
        }
        do {
            return try JSONDecoder.mt.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// FastAPI errors carry `{"detail": "..."}`.
    private static func detail(from data: Data) -> String? {
        struct Body: Decodable { var detail: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.detail
    }
}

public struct MatchQuery: Sendable, Equatable {
    public var seasonId: Int?
    public var ageGroupId: Int?
    public var divisionId: Int?
    public var teamId: Int?
    public var matchType: String?
    /// `YYYY-MM-DD`, inclusive.
    public var startDate: String?
    public var endDate: String?

    public init(seasonId: Int? = nil, ageGroupId: Int? = nil, divisionId: Int? = nil, teamId: Int? = nil,
                matchType: String? = nil, startDate: String? = nil, endDate: String? = nil) {
        self.seasonId = seasonId
        self.ageGroupId = ageGroupId
        self.divisionId = divisionId
        self.teamId = teamId
        self.matchType = matchType
        self.startDate = startDate
        self.endDate = endDate
    }

    var items: [String: String?] {
        ["season_id": seasonId.map(String.init), "age_group_id": ageGroupId.map(String.init),
         "division_id": divisionId.map(String.init), "team_id": teamId.map(String.init),
         "match_type": matchType, "start_date": startDate, "end_date": endDate]
    }
}
