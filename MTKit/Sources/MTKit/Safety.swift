import Foundation

// Chat safety (SB-1309, App Review guideline 1.2): report a message, block its author,
// list and lift blocks. Backend: POST /api/matches/{id}/live/events/{id}/report,
// POST|DELETE /api/users/{id}/block, GET /api/users/me/blocks.

public enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam, harassment, hate, sexual, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment"
        case .hate: "Hate Speech"
        case .sexual: "Sexual Content"
        case .other: "Something Else"
        }
    }
}

/// Row from `GET /api/users/me/blocks`.
public struct BlockedUser: Codable, Sendable, Equatable, Identifiable {
    public var userId: String
    public var username: String?
    public var createdAt: String?

    public var id: String { userId }
    public var displayName: String { username ?? "Unknown user" }

    public init(userId: String, username: String? = nil, createdAt: String? = nil) {
        self.userId = userId
        self.username = username
        self.createdAt = createdAt
    }
}

/// Why the backend refused a chat message, in words for the composer.
public enum ChatPostError: Error, Equatable, Sendable, LocalizedError {
    /// 422: the word filter matched.
    case notAllowed
    /// 403: the user has been banned from chat.
    case banned
    /// 429: more than 10 messages a minute.
    case rateLimited

    init?(_ error: APIError) {
        guard case .http(let status, _) = error else { return nil }
        switch status {
        case 422: self = .notAllowed
        case 403: self = .banned
        case 429: self = .rateLimited
        default: return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notAllowed: "That message contains language that isn't allowed."
        case .banned: "You can no longer post in chat."
        case .rateLimited: "You're sending messages too fast."
        }
    }
}

struct ReportRequest: Encodable, Sendable {
    var reason: ReportReason
    var details: String?

    enum CodingKeys: String, CodingKey { case reason, details }

    /// `details` is always sent, as `null` when empty.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason.rawValue, forKey: .reason)
        try container.encode(details, forKey: .details)
    }
}

struct ReportResponse: Decodable, Sendable {
    var blockedUserId: String
}

extension MatchEvent {
    /// Whether this is a chat message written by someone in `blocked`. Only chat is hidden:
    /// goals, cards and subs a blocked manager records stay visible.
    public func isChat(byAnyOf blocked: Set<String>) -> Bool {
        guard kind == .message, let author = createdBy else { return false }
        return blocked.contains(author)
    }

    /// `events` without chat messages from anyone in `blocked`. The server already leaves them out;
    /// this covers the gap between blocking someone and the next fetch.
    public static func visible(_ events: [MatchEvent], hiding blocked: Set<String>) -> [MatchEvent] {
        guard !blocked.isEmpty else { return events }
        return events.filter { !$0.isChat(byAnyOf: blocked) }
    }
}

extension APIClient {
    /// Report a chat message. The backend also blocks its author for the caller; returns that author's id.
    @discardableResult
    public func reportEvent(matchId: Int, eventId: Int, reason: ReportReason, details: String? = nil)
        async throws -> String {
        let response: ReportResponse = try await send(
            "POST", "/api/matches/\(matchId)/live/events/\(eventId)/report",
            body: ReportRequest(reason: reason, details: details))
        return response.blockedUserId
    }

    public func blockUser(id: String) async throws {
        try await sendIgnoringBody("POST", "/api/users/\(id)/block")
    }

    public func unblockUser(id: String) async throws {
        try await sendIgnoringBody("DELETE", "/api/users/\(id)/block")
    }

    public func blocks() async throws -> [BlockedUser] { try await get("/api/users/me/blocks") }
}
