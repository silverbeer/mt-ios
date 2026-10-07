import Foundation
import os

/// Outcome of checking a saved session on launch.
public enum SessionCheck: Sendable, Equatable {
    /// No saved session, or the backend rejected it (refresh included).
    case signedOut
    case signedIn(User, MyProfile?)
    /// The session is kept, but the backend didn't answer in time or failed. The user
    /// gets Retry / Sign Out rather than a spinner.
    case unreachable(APIError)
}

extension APIClient {
    static let log = Logger(subsystem: "com.missingtable", category: "auth")

    /// Launch check: one `/api/auth/me` (refreshing the token if needed) for both the user
    /// and the profile, bounded by `limit` in total. Logs how long it took and how it ended — never tokens.
    public func checkSession(within limit: Duration = .seconds(12)) async -> SessionCheck {
        guard isSignedIn else { return .signedOut }
        let start = ContinuousClock.now
        let outcome: SessionCheck
        do {
            let response: LaunchMe = try await withDeadline(limit) { try await self.get("/api/auth/me") }
            outcome = .signedIn(response.me.asUser, response.profile?.profile)
        } catch APIError.unauthorized {
            outcome = .signedOut
        } catch let error as APIError {
            outcome = .unreachable(error)
        } catch {
            outcome = .unreachable(.transport(error.localizedDescription))
        }
        let elapsed = ContinuousClock.now - start
        Self.log.info("launch check: \(outcome.logLabel, privacy: .public) in \(elapsed, privacy: .public)")
        return outcome
    }
}

/// `/api/auth/me` read once as both `me()` and `profile()` see it. A profile that
/// doesn't decode doesn't block sign-in.
private struct LaunchMe: Decodable, Sendable {
    var me: MeResponse
    var profile: ProfileEnvelope?

    init(from decoder: any Decoder) throws {
        me = try MeResponse(from: decoder)
        profile = try? ProfileEnvelope(from: decoder)
    }
}

extension SessionCheck {
    var logLabel: String {
        switch self {
        case .signedOut: "signed out"
        case .signedIn: "signed in"
        case .unreachable(let error): "unreachable (\(error))"
        }
    }
}

/// Runs `operation`, throwing `APIError.transport` if it outlives `limit`.
///
/// Stops waiting at the deadline and cancels `operation`, but doesn't wait for it to wind
/// down: a token refresh runs in a task shared with other callers, which cancellation
/// doesn't reach (and shouldn't — the server may already have rotated the token). A task
/// group would sit on it until URLSession's own 60 s timeout.
func withDeadline<T: Sendable>(_ limit: Duration,
                               _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let outcome = OneShot<T>()
    let work = Task {
        do { outcome.finish(.success(try await operation())) } catch { outcome.finish(.failure(error)) }
    }
    let timer = Task {
        try await Task.sleep(for: limit)
        outcome.finish(.failure(APIError.transport(
            "No answer within \(limit.formatted(.units(allowed: [.seconds])))")))
    }
    defer {
        work.cancel()
        timer.cancel()
    }
    return try await withTaskCancellationHandler {
        try await outcome.value()
    } onCancel: {
        outcome.finish(.failure(CancellationError()))
    }
}

/// The first result wins; later ones are dropped.
private final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, any Error>?
    private var waiter: CheckedContinuation<T, any Error>?

    func finish(_ result: Result<T, any Error>) {
        let waiter: CheckedContinuation<T, any Error>? = lock.withLock {
            guard self.result == nil else { return nil }
            self.result = result
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume(with: result)
    }

    func value() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let ready: Result<T, any Error>? = lock.withLock {
                if result == nil { waiter = continuation }
                return result
            }
            if let ready { continuation.resume(with: ready) }
        }
    }
}
