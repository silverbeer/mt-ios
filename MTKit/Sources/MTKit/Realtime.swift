import Foundation
import os

/// Supabase Realtime endpoint and the project's public anon key. The anon key is
/// public by design (the web app ships it); database row-level security, not the
/// key, decides what it can read, and it can't write match events.
public struct RealtimeConfig: Sendable, Equatable {
    public var url: URL
    public var anonKey: String

    public static let production = RealtimeConfig(
        url: URL(string: "wss://ppgxasqgqbnauvxozmjw.supabase.co/realtime/v1/websocket")!,
        anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBwZ3hhc3FncWJuYXV2eG96bWp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk1ODQ1NTgsImV4cCI6MjA3NTE2MDU1OH0.q-H9jS8fnPXyFY5M0rq5MO3_8dniFu5OxaKhL1r_2TU") // pragma: allowlist secret gitleaks:allow (public anon key)

    /// Local Supabase CLI demo key, the same for every local instance.
    public static let local = RealtimeConfig(
        url: URL(string: "ws://localhost:55321/realtime/v1/websocket")!,
        anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0") // pragma: allowlist secret gitleaks:allow (public anon key)
}

extension APIEnvironment {
    public var realtime: RealtimeConfig {
        switch self {
        case .production: .production
        case .local: .local
        }
    }
}

/// "Something changed on this match" signals from Supabase Realtime, as the web's
/// useLiveMatch subscribes to postgres_changes on match_events and matches.
///
/// Callers re-read through the API on each signal rather than trusting the payload,
/// and keep a slow poll as a fallback. The stream reconnects after drops until the
/// consumer stops iterating.
public enum MatchRealtime {
    static let log = Logger(subsystem: "com.missingtable", category: "realtime")

    public static func changes(matchId: Int, config: RealtimeConfig,
                               session: URLSession = .shared) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await listen(matchId: matchId, config: config, session: session) { continuation.yield() }
                    try? await Task.sleep(for: .seconds(5))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One socket lifetime: join, heartbeat, forward change events until it closes.
    private static func listen(matchId: Int, config: RealtimeConfig, session: URLSession,
                               onChange: @escaping @Sendable () -> Void) async {
        var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apikey", value: config.anonKey),
                                 URLQueryItem(name: "vsn", value: "1.0.0")]
        let socket = session.webSocketTask(with: components.url!)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        guard let join = try? joinMessage(matchId: matchId, anonKey: config.anonKey, ref: "1"),
              (try? await socket.send(.data(join))) != nil else { return }

        let heartbeat = Task {
            var ref = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                ref += 1
                guard let beat = try? heartbeatMessage(ref: String(ref)),
                      (try? await socket.send(.data(beat))) != nil else { return }
            }
        }
        defer { heartbeat.cancel() }

        while !Task.isCancelled {
            guard let message = try? await socket.receive() else { return }
            let data: Data? = switch message {
            case .data(let data): data
            case .string(let text): Data(text.utf8)
            @unknown default: nil
            }
            switch data.map(classify) {
            case .change: onChange()
            case .closed:
                log.info("match \(matchId, privacy: .public): channel closed")
                return
            case .joined: log.info("match \(matchId, privacy: .public): joined")
            case .other, nil: continue
            }
        }
    }

    // MARK: Phoenix protocol

    struct Envelope<Payload: Encodable>: Encodable {
        var topic: String
        var event: String
        var payload: Payload
        var ref: String
    }

    struct JoinPayload: Encodable {
        struct Config: Encodable {
            struct Broadcast: Encodable {
                var ack = false
                var selfBroadcast = false
                enum CodingKeys: String, CodingKey { case ack, selfBroadcast = "self" }
            }
            struct Presence: Encodable { var key = "" }
            struct Change: Encodable {
                var event = "*"
                var schema = "public"
                var table: String
                var filter: String
            }
            var broadcast = Broadcast()
            var presence = Presence()
            var postgres_changes: [Change]
        }
        var config: Config
        var access_token: String
    }

    static func topic(matchId: Int) -> String { "realtime:match-\(matchId)" }

    static func joinMessage(matchId: Int, anonKey: String, ref: String) throws -> Data {
        let payload = JoinPayload(config: .init(postgres_changes: [
            .init(table: "match_events", filter: "match_id=eq.\(matchId)"),
            .init(table: "matches", filter: "id=eq.\(matchId)"),
        ]), access_token: anonKey)
        return try JSONEncoder().encode(Envelope(topic: topic(matchId: matchId), event: "phx_join",
                                                 payload: payload, ref: ref))
    }

    static func heartbeatMessage(ref: String) throws -> Data {
        try JSONEncoder().encode(Envelope(topic: "phoenix", event: "heartbeat", payload: [String: String](), ref: ref))
    }

    enum Incoming: Equatable { case change, closed, joined, other }

    static func classify(_ data: Data) -> Incoming {
        struct Header: Decodable {
            var event: String
            var payload: Payload?
            var ref: String?
            struct Payload: Decodable { var status: String? }
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .other }
        switch header.event {
        case "postgres_changes": return .change
        case "phx_close", "phx_error": return .closed
        case "phx_reply" where header.payload?.status == "error": return .closed
        case "phx_reply" where header.payload?.status == "ok" && header.ref == "1": return .joined
        default: return .other
        }
    }
}
